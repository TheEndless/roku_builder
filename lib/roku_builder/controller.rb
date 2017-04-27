# ********** Copyright Viacom, Inc. Apache 2.0 **********

module RokuBuilder

  # Controls all interaction with other classes
  class Controller

    # Run the builder
    # @param options [Hash] The options hash
    def self.run(options:)
      initialize_logger(options: options)

      # Validate Options
      options_code = validate_options(options: options)
      ErrorHandler.handle_options_codes(options_code: options_code, options: options, logger: Logger.instance)

      # Configure Gem
      configure_code = configure(options: options, logger: Logger.instance)
      ErrorHandler.handle_configure_codes(configure_code: configure_code, logger: Logger.instance)

      # Load Config
      config = Config.new(options: options)
      config.load
      config.validate
      config.parse

      # Check devices
      device_code = check_devices(options: options, config: config, logger: Logger.instance)
      ErrorHandler.handle_device_codes(device_code: device_code, logger: Logger.instance)

      # Run Commands
      command_code = execute_commands(options: options, config: config, logger: Logger.instance)
      ErrorHandler.handle_command_codes(command_code: command_code, logger: Logger.instance)
    end

    def self.initialize_logger(options:)
      if options[:debug]
        Logger.set_debug
      elsif options[:verbose]
        Logger.set_info
      else
        Logger.set_warn
      end

      logger = Logger.instance
    end

    # Validates the user options
    # @param options [Hash] The options hash
    # @return [Integer] Status code for command validation
    def self.validate_options(options:)
      command_result = validate_command_options(options: options)
      return command_result unless command_result == VALID
      source_result = validate_source_options(options: options)
      return source_result unless source_result == VALID
      combination_result = validate_option_combinations(options: options)
      return combination_result unless combination_result == VALID
      return validate_depricated_commands(options: options)
    end
    private_class_method :validate_options

    # Validates use of command options
    # @param options [Hash] The options hash
    # @return [Integer] Status code for command validation
    def self.validate_command_options(options:)
      all_commands = options.keys & commands
      return EXTRA_COMMANDS if all_commands.count > 1
      return NO_COMMANDS if all_commands.count < 1
      VALID
    end
    private_class_method :validate_command_options

    # Validates use of source options
    # @param options [Hash] The options hash
    # @return [Integer] Status code for command validation
    def self.validate_source_options(options:)
      all_sources = options.keys & sources
      return EXTRA_SOURCES if all_sources.count > 1
      if (options.keys & source_commands).count == 1
        return NO_SOURCE unless all_sources.count == 1
      end
      VALID
    end
    private_class_method :validate_source_options

    # Validates proper option combinations
    # @param options [Hash] The options hash
    # @return [Integer] Status code for command validation
    def self.validate_option_combinations(options:)
      all_sources = options.keys & sources
      if all_sources.include?(:current)
        return BAD_CURRENT unless options[:build] or options[:sideload]
      end
      if options[:in]
        return BAD_IN_FILE unless options[:sideload]
      end
      VALID
    end
    private_class_method :validate_option_combinations

    # Validate depricated options adn commands
    # @param options [Hash] The Options hash
    # @return [Integer] Status code for command validation
    def self.validate_depricated_commands(options:)
      depricated = options.keys & depricated_options.keys
      if depricated.count > 0
        return DEPRICATED
      end
      VALID
    end
    private_class_method :validate_depricated_commands

    # Run commands
    # @param options [Hash] The options hash
    # @return [Integer] Return code for options handeling
    # @param logger [Logger] system logger
    def self.execute_commands(options:, config:, logger:)
      command = (commands & options.keys).first
      if ControllerCommands.simple_commands.keys.include?(command)
        params = ControllerCommands.simple_commands[command]
        params[:config] = config
        params[:logger] = logger
        ControllerCommands.simple_command(**params)
      else
        params = ControllerCommands.method(command.to_s).parameters.collect{|a|a[1]}
        args = {}
        params.each do |key|
          case key
          when :options
            args[:options] = options
          when :config
            args[:config] = config
          when :logger
            args[:logger] = logger
          end
        end
        ControllerCommands.send(command, args)
      end
    end
    private_class_method :execute_commands

    # Ensure that the selected device is accessable
    # @param options [Hash] The options hash
    # @param logger [Logger] system logger
    def self.check_devices(options:, config:, logger:)
      command = (options.keys & commands).first
      if device_commands.include?(command)
        ping = Net::Ping::External.new
        host = config.parsed[:device_config][:ip]
        return GOOD_DEVICE if ping.ping? host, 1, 0.2, 1
        return BAD_DEVICE if options[:device_given]
        config.raw[:devices].each_pair {|key, value|
          unless key == :default
            host = value[:ip]
            if ping.ping? host, 1, 0.2, 1
              config.parsed[:device_config] = value
              config.parsed[:device_config][:logger] = logger
              return CHANGED_DEVICE
            end
          end
        }
        return NO_DEVICES
      end
      return GOOD_DEVICE
    end
    private_class_method :check_devices

    # List of command options
    # @return [Array<Symbol>] List of command symbols that can be used in the options hash
    def self.commands
      [:sideload, :package, :test, :deeplink,:configure, :validate, :delete,
        :navigate, :navigator, :text, :build, :monitor, :update, :screencapture,
        :key, :genkey, :screen, :screens, :applist, :print, :profile, :dostage,
        :dounstage]
    end

    # List of depricated options
    # @return [Hash] Hash of depricated options and the warning message for each
    def self.depricated_options
      {deeplink_depricated: "-L and --deeplink are depricated. Use -o or --deeplink-options." }
    end

    # List of source options
    # @return [Array<Symbol>] List of source symbols that can be used in the options hash
    def self.sources
      [:ref, :set_stage, :working, :current, :in]
    end

    # List of commands requiring a source option
    # @return [Array<Symbol>] List of command symbols that require a source in the options hash
    def self.source_commands
      [:sideload, :package, :test, :build, :key, :update, :print]
    end

    # List of commands the activate the exclude files
    # @return [Array<Symbol] List of commands the will activate the exclude files lists
    def self.exclude_commands
      [:build, :package]
    end

    # List of commands that require a device
    # @return [Array<Symbol>] List of commands that require a device
    def self.device_commands
      [:sideload, :package, :test, :deeplink, :delete, :navigate, :navigator,
        :text, :monitor, :screencapture, :applist, :profile, :key, :genkey ]
    end

    def self.exclude_command?(options:)
      all_commands = options.keys & commands
      (all_commands & exclude_commands).count > 0
    end

    # Configure the gem
    # @param options [Hash] The options hash
    # @return [Integer] Success or failure code
    # @param logger [Logger] system logger
    def self.configure(options:, logger:)
      if options[:configure]
        source_config = File.expand_path(File.join(File.dirname(__FILE__), "..", '..', 'config.json.example'))
        target_config = File.expand_path(options[:config])
        if File.exist?(target_config)
          unless options[:edit_params]
            return CONFIG_OVERWRITE
          end
        else
          ### Copy Config File ###
          FileUtils.copy(source_config, target_config)
        end
        if options[:edit_params]
          config = Config.new(options: options)
          config.load
          config.edit
        end
        return SUCCESS
      end
      nil
    end
    private_class_method :configure

    # Run a system command
    # @param command [String] The command to be run
    # @return [String] The output of the command
    def self.system(command:)
      `#{command}`.chomp
    end
  end
end
