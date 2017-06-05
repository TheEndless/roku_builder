# ********** Copyright Viacom, Inc. Apache 2.0 **********

module RokuBuilder
  class Options < Hash
    def initialize(options: nil)
      @logger = Logger.instance
      setup_plugin_commands
      options ||= parse
      merge!(options)
    end

    def validate
      validate_commands
      validate_sources
      validate_deprivated
    end

    def command
      (keys & commands).first
    end

    def exclude_command?
      exclude_commands.include?(command)
    end

    def source_command?
      source_commands.include?(command)
    end

    def device_command?
      device_commands.include?(command)
    end

    def has_source?
      !(keys & sources).empty?
    end

    private

    def setup_plugin_commands
      RokuBuilder.plugins.each do |plugin|
        plugin.commands.each do |command, attributes|
          commands << command
          [:device, :source, :exclude].each do |type|
            if attributes[type]
              send("#{type}_commands".to_sym) << command
            end
          end
        end
      end
    end

    def parse
      options = {}
      options[:config] = '~/.roku_config.json'
      options[:update_manifest] = false
      parser = build_parser(options: options)
      add_plugin_options(parser: parser, options:options)
      validate_parser(parser: parser)
      begin
        parser.parse!
      rescue StandardError => e
        @logger.fatal e.message
        exit
      end
      options
    end

    def build_parser(options:)
      OptionParser.new do |opts|
        opts.banner = "Usage: roku <command> [options]"
        opts.separator "Core Comamnads:"
        opts.on("--configure", "Copy base configuration file to the --config location. Default: '~/.roku_config.json'") do
          options[:configure] = true
        end
        opts.on("--validate", "Validate configuration'") do
          options[:validate] = true
        end
        opts.on("--do-stage", "Run the stager. Used for scripting. Always run --do-unstage after") do
          options[:dostage] = true
        end
        opts.on("--do-unstage", "Run the unstager. Used for scripting. Always run --do-script first") do
          options[:dounstage] = true
        end
        opts.separator ""
        opts.separator "Config Options:"
        opts.on("-e", "--edit PARAMS", "Edit config params when configuring. (eg. a:b, c:d,e:f)") do |p|
          options[:edit_params] = p
        end
        opts.on("--config CONFIG", "Set a custom config file. Default: '~/.roku_config.json'") do |c|
          options[:config] = c
        end
        opts.separator ""
        opts.separator "Source Options:"
        opts.on("-r", "--ref REF", "Git referance to use for sideloading") do |r|
          options[:ref] = r
        end
        opts.on("-w", "--working", "Use working directory to sideload or test") do
          options[:working] = true
        end
        opts.on("-c", "--current", "Use current directory to sideload or test. Overrides any project config") do
          options[:current] = true
        end
        opts.on("-s", "--stage STAGE", "Set the stage to use. Default: 'production'") do |b|
          options[:stage] = b
          options[:set_stage] = true
        end
        opts.on("-P", "--project ID", "Use a different project") do |p|
          options[:project] = p
        end
        opts.separator ""
        opts.separator "Other Options:"
        opts.on("-O", "--out PATH", "Output file/folder. If PATH ends in .pkg/.zip/.jpg, file is assumed, otherwise folder is assumed") do |o|
          options[:out] = o
        end
        opts.on("-I", "--in PATH", "Input file for sideloading") do |i|
          options[:in] = i
        end
        opts.on("-D", "--device ID", "Use a different device corresponding to the given ID") do |d|
          options[:device] = d
          options[:device_given] = true
        end
        opts.on("-V", "--verbose", "Print Info message") do
          options[:verbose] = true
        end
        opts.on("--debug", "Print Debug messages") do
          options[:debug] = true
        end
        opts.on("-h", "--help", "Show this message") do
          puts opts
          exit
        end
        opts.on("-v", "--version", "Show version") do
          puts RokuBuilder::VERSION
          exit
        end
      end
    end

    def add_plugin_options(parser:, options:)
      RokuBuilder.plugins.each do |plugin|
        plugin.parse_options(parser: parser, options: options)
      end
    end

    def validate_parser(parser:)
      short = []
      long = []
      stack = parser.instance_variable_get(:@stack)
      stack.each do |optionsList|
        optionsList.each_option do |option|
          if short.include?(option.short)
            raise ImplementationError, "Duplicate option defined: #{option.short}"
          end
          short.push(option.short)
          if long.include?(option.long)
            raise ImplementationError, "Duplicate option defined: #{option.long}"
          end
          long.push(option.long)
        end
      end
    end

    def validate_commands
      all_commands = keys & commands
      raise InvalidOptions, "Only specify one command" if all_commands.count > 1
      raise InvalidOptions, "Specify at least one command" if all_commands.count < 1
    end

    def validate_sources
      all_sources = keys & sources
      raise InvalidOptions, "Only spefify one source" if all_sources.count > 1
      if source_command? and !has_source?
        raise InvalidOptions, "Must specify a source for that command"
      end
    end

    def validate_deprivated
      depricated = keys & depricated_options.keys
      if depricated.count > 0
        depricated.each do |key|
          @logger.warn depricated_options[key]
        end
      end
    end

    # List of command options
    # @return [Array<Symbol>] List of command symbols that can be used in the options hash
    def commands
      @commands ||= [:configure, :validate, :dostage, :dounstage]
    end

    # List of depricated options
    # @return [Hash] Hash of depricated options and the warning message for each
    def depricated_options
      @depricated_options ||= {}
    end

    # List of source options
    # @return [Array<Symbol>] List of source symbols that can be used in the options hash
    def sources
      [:ref, :set_stage, :working, :current, :in]
    end

    # List of commands requiring a source option
    # @return [Array<Symbol>] List of command symbols that require a source in the options hash
    def source_commands
      @source_commands ||= []
    end

    # List of commands the activate the exclude files
    # @return [Array<Symbol] List of commands the will activate the exclude files lists
    def exclude_commands
      @exclude_commands ||= []
    end

    # List of commands that require a device
    # @return [Array<Symbol>] List of commands that require a device
    def device_commands
      @device_commands ||= []
    end
  end
end
