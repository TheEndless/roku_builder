# ********** Copyright Viacom, Inc. Apache 2.0 **********

require_relative "../test_helper.rb"

module RokuBuilder
  class PackagerTest < Minitest::Test
    def setup
      Logger.set_testing
      RokuBuilder.setup_plugins
      register_plugins(Packager)
      @requests = []
    end
    def teardown
      @requests.each {|req| remove_request_stub(req)}
    end
    def test_packager_current
      config, options = [nil, nil]
      Pathname.stub(:pwd, test_files_path(PackagerTest)) do
        config, options = build_config_options_objects(PackagerTest, {package: true, current: true}, false)
      end
      packager = Packager.new(config: config)
      assert_raises InvalidOptions do
        packager.package(options: options)
      end
    end
    def test_packager_in
      config, options = build_config_options_objects(PackagerTest, {package: true, in: "/tmp/test.pkg"}, false)
      packager = Packager.new(config: config)
      assert_raises InvalidOptions do
        packager.package(options: options)
      end
    end
    def test_packager_ref
      config, options = build_config_options_objects(PackagerTest, {package: true, ref: "test_ref"}, false)
      packager = Packager.new(config: config)
      assert_raises InvalidOptions do
        packager.package(options: options)
      end
    end
    def test_packager_package_failed
      config, options = build_config_options_objects(PackagerTest, {package: true, stage: "production"}, false)
      @requests.push(stub_request(:post, "http://192.168.0.100:8060/keypress/Home").
        to_return(status: 200, body: "", headers: {}))
      @requests.push(stub_request(:post, "http://192.168.0.100/plugin_install").
        to_return(status: 200, body: "", headers: {}))
      @requests.push(stub_request(:post, "http://192.168.0.100/plugin_package").
        to_return(status: 200, body: "Failed: Error.", headers: {}))
      packager = Packager.new(config: config)
      assert_raises ExecutionError do
        packager.package(options: options)
      end
    end

    def test_packager_package
      loader = Minitest::Mock.new
      io = Minitest::Mock.new
      config, options = build_config_options_objects(PackagerTest, {package: true, stage: "production"}, false)

      @requests.push(stub_request(:post, "http://192.168.0.100/plugin_inspect").
        to_return(status: 200, body: "", headers: {}).times(2))
      body = "<a href=\"pkgs\">pkg_url</a>"
      @requests.push(stub_request(:post, "http://192.168.0.100/plugin_package").
        to_return(status: 200, body: body, headers: {}).times(2))
      body = "package_body"
      @requests.push(stub_request(:get, "http://192.168.0.100/pkgs/pkg_url").
        to_return(status: 200, body: body, headers: {}))

      loader.expect(:sideload, nil, [Hash])
      io.expect(:write, nil, ["package_body"])

      packager = Packager.new(config: config)
      dev_id = Proc.new {"#{Random.rand(999999999999)}"}
      Loader.stub(:new, loader) do
        Time.stub(:now, Time.at(0)) do
          File.stub(:open, nil, io) do
            packager.stub(:dev_id, dev_id) do
              packager.package(options: options)
            end
          end
        end
      end
      io.verify
    end
    def test_packager_dev_id
      body = "v class=\"roku-font-5\"><label>Your Dev ID: &nbsp;</label> dev_id<hr></div>"
      @requests.push(stub_request(:get, "http://192.168.0.100/plugin_package").
        to_return(status: 200, body: body, headers: {}))

      config = build_config_options_objects(PackagerTest, {key: true, stage: "production"}, false)[0]
      packager = Packager.new(config: config)
      dev_id = packager.dev_id

      assert_equal "dev_id", dev_id
    end
    def test_packager_dev_id_old_interface
      body = "<p> Your Dev ID: <font face=\"Courier\">dev_id</font> </p>"
      @requests.push(stub_request(:get, "http://192.168.0.100/plugin_package").
        to_return(status: 200, body: body, headers: {}))

      config = build_config_options_objects(PackagerTest, {key: true, stage: "production"}, false)[0]
      packager = Packager.new(config: config)
      dev_id = packager.dev_id

      assert_equal "dev_id", dev_id
    end

    def test_packager_key_changed
      @requests.push(stub_request(:post, "http://192.168.0.100/plugin_inspect").
        to_return(status: 200, body: "", headers: {}))
      logger = Minitest::Mock.new
      logger.expect(:debug, nil) {|s| s =~ /\d* -> \d*/}
      dev_id = Proc.new {"#{Random.rand(999999999999)}"}
      config, options = build_config_options_objects(PackagerTest, {key: true, stage: "production"}, false)
      packager = Packager.new(config: config)
      Logger.class_variable_set(:@@instance, logger)
      packager.stub(:dev_id, dev_id) do
        packager.key(options: options)
      end
    end

    def test_packager_key_same
      @requests.push(stub_request(:post, "http://192.168.0.100/plugin_inspect").
        to_return(status: 200, body: "", headers: {}))
      logger = Minitest::Mock.new
      logger.expect(:info, nil) {|s| s =~ /did not change/}
      logger.expect(:debug, nil) {|s| s =~ /\d* -> \d*/}
      dev_id = Proc.new {"#{Random.rand(999999999999)}"}
      config, options = build_config_options_objects(PackagerTest, {key: true, stage: "production"}, false)
      packager = Packager.new(config: config)
      Logger.class_variable_set(:@@instance, logger)
      packager.stub(:dev_id, dev_id) do
        packager.key(options: options)
      end
    end

    def test_packager_generate_new_key
      connection = Minitest::Mock.new()
      connection.expect(:puts, nil, ["genkey"])
      connection.expect(:waitfor, nil) do |config, &blk|
        assert_equal(/./, config['Match'])
        assert_equal(false, config['Timeout'])
        txt = "Password: password\nDevID: devid\n"
        blk.call(txt)
        true
      end
      connection.expect(:close, nil, [])

      config = build_config_options_objects(PackagerTest, {genkey: true}, false)[0]
      packager = Packager.new(config: config)
      Net::Telnet.stub(:new, connection) do
        packager.send(:generate_new_key)
      end
    end

    def test_packager_genkey
      loader = Minitest::Mock.new
      loader.expect(:sideload, nil, [Hash])

      body = "<a href=\"pkgs\">pkg_url</a>"
      @requests.push(stub_request(:post, "http://192.168.0.100/plugin_package").
         to_return(status: 200, body: body, headers: {}))
      @requests.push(stub_request(:get, "http://192.168.0.100/pkgs/pkg_url").
        to_return(status: 200, body: "", headers: {}))
      config, options = build_config_options_objects(PackagerTest, {genkey: true}, false)
      packager = Packager.new(config: config)
      Loader.stub(:new, loader) do
        packager.stub(:generate_new_key, ["password", "dev_id"]) do
          packager.genkey(options: options)
        end
      end

      loader.verify
    end
  end
end
