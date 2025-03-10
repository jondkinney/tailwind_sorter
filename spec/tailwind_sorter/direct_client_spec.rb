require 'spec_helper'
require 'fileutils'

RSpec.describe TailwindSorter::DirectClient do
  let(:test_classes) { "p-4 flex mt-2" }
  let(:sample_config) do
    <<~JS
      module.exports = {
        content: ['*.html'],
        theme: { extend: {} },
        plugins: []
      }
    JS
  end
  let(:sample_css) do
    <<~CSS
      @tailwind base;
      @tailwind components;
      @tailwind utilities;
    CSS
  end

  def create_test_files(config_path:, css_path: nil)
    FileUtils.mkdir_p(File.dirname(config_path))
    File.write(config_path, sample_config)

    if css_path
      FileUtils.mkdir_p(File.dirname(css_path))
      File.write(css_path, sample_css)
    end
  end

  describe "config file detection" do
    let(:root_dir) { Dir.pwd }
    let(:test_paths) do
      [
        File.join(root_dir, "tailwind.config.js"),
        File.join(root_dir, "tailwind.config.cjs"),
        File.join(root_dir, "tailwind.config.mjs"),
        File.join(root_dir, "tailwind.config.ts"),
        File.join(root_dir, "config"),
        File.join(root_dir, "styles.css"),
        File.join(root_dir, "src"),
        File.join(root_dir, "app"),
        File.join(root_dir, "assets")
      ]
    end

    before(:each) { cleanup_test_files(*test_paths) }
    after(:each) { cleanup_test_files(*test_paths) }

    it "finds config in root directory" do
      config_path = File.join(root_dir, "tailwind.config.js")
      css_path = File.join(root_dir, "styles.css")
      create_test_files(config_path: config_path, css_path: css_path)

      client = described_class.new
      expect(client.instance_variable_get(:@config_path)).to eq(config_path)
      expect(client.instance_variable_get(:@css_path)).to eq(css_path)

      # Verify sorting still works
      sorted = client.sort_classes(test_classes)
      expect(sorted).to eq("mt-2 flex p-4")
    end

    it "finds config in config directory" do
      config_path = File.join(root_dir, "config", "tailwind.config.js")
      css_path = File.join(root_dir, "app/assets/stylesheets/application.tailwind.css")
      create_test_files(config_path: config_path, css_path: css_path)

      client = described_class.new
      expect(client.instance_variable_get(:@config_path)).to eq(config_path)
      expect(client.instance_variable_get(:@css_path)).to eq(css_path)

      # Verify sorting still works
      sorted = client.sort_classes(test_classes)
      expect(sorted).to eq("mt-2 flex p-4")
    end

    it "finds alternative config file types" do
      config_path = File.join(root_dir, "tailwind.config.cjs")
      css_path = File.join(root_dir, "src/styles.css")
      create_test_files(config_path: config_path, css_path: css_path)

      client = described_class.new
      expect(client.instance_variable_get(:@config_path)).to eq(config_path)
      expect(client.instance_variable_get(:@css_path)).to eq(css_path)

      # Verify sorting still works
      sorted = client.sort_classes(test_classes)
      expect(sorted).to eq("mt-2 flex p-4")
    end

    it "falls back to temporary files when no config found" do
      client = described_class.new
      expect(client.instance_variable_get(:@config_path)).to be_nil
      expect(client.instance_variable_get(:@css_path)).to be_nil

      # Should create temp files when started
      client.start
      temp_dir = client.instance_variable_get(:@temp_dir)
      expect(temp_dir).not_to be_nil
      expect(File.exist?(File.join(temp_dir, "tailwind.config.js"))).to be true
      expect(File.exist?(File.join(temp_dir, "styles.css"))).to be true

      # Verify sorting still works
      sorted = client.sort_classes(test_classes)
      expect(sorted).to eq("mt-2 flex p-4")

      # Verify server stops but keeps temp dir for reuse
      client.stop
      expect(Dir.exist?(temp_dir)).to be true
      expect(client.instance_variable_get(:@stdin)).to be_nil

      # Cleanup at end of test
      client.cleanup if client.respond_to?(:cleanup)
    end

    it "finds CSS file in various locations" do
      css_locations = [
        "styles.css",
        "app/assets/stylesheets/application.tailwind.css",
        "src/styles.css",
        "assets/css/styles.css"
      ]

      css_locations.each do |css_location|
        cleanup_test_files(
          File.join(root_dir, "tailwind.config.js"),
          File.join(root_dir, "config"),
          File.join(root_dir, "styles.css"),
          File.join(root_dir, "src"),
          File.join(root_dir, "app"),
          File.join(root_dir, "assets")
        )

        config_path = File.join(root_dir, "tailwind.config.js")
        css_path = File.join(root_dir, css_location)
        create_test_files(config_path: config_path, css_path: css_path)

        client = described_class.new
        expect(client.instance_variable_get(:@config_path)).to eq(config_path)
        expect(client.instance_variable_get(:@css_path)).to eq(css_path)

        # Verify sorting still works
        sorted = client.sort_classes(test_classes)
        expect(sorted).to eq("mt-2 flex p-4")
      end
    end
  end
end