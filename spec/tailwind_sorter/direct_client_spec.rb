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
    # Remove any existing test files first
    cleanup_test_files(config_path, css_path)

    # Create new files
    FileUtils.mkdir_p(File.dirname(config_path))
    File.write(config_path, sample_config)

    if css_path
      FileUtils.mkdir_p(File.dirname(css_path))
      File.write(css_path, sample_css)
    end
  end

  def cleanup_test_files(*paths)
    paths.each do |path|
      next unless path
      begin
        if File.directory?(path)
          FileUtils.rm_rf(path)
        else
          FileUtils.rm_f(path)
          # Also clean up parent directories if they're empty
          dir = File.dirname(path)
          while dir != "." && dir != "/" && Dir.exist?(dir)
            begin
              Dir.rmdir(dir)
              dir = File.dirname(dir)
            rescue Errno::ENOTEMPTY, Errno::ENOENT, Errno::EACCES
              break
            end
          end
        end
      rescue Errno::ENOENT, Errno::EACCES => e
        warn "Warning: Could not remove #{path}: #{e.message}"
      end
    end
  end

  describe "config file detection" do
    let(:root_dir) { Dir.pwd }

    after(:each) do
      # Clean up any test files we created
      cleanup_test_files(
        File.join(root_dir, "tailwind.config.js"),
        File.join(root_dir, "tailwind.config.cjs"),
        File.join(root_dir, "tailwind.config.mjs"),
        File.join(root_dir, "tailwind.config.ts"),
        File.join(root_dir, "config"),
        File.join(root_dir, "styles.css"),
        File.join(root_dir, "src"),
        File.join(root_dir, "app"),
        File.join(root_dir, "assets")
      )
    end

    before(:each) do
      # Ensure a clean state before each test
      cleanup_test_files(
        File.join(root_dir, "tailwind.config.js"),
        File.join(root_dir, "tailwind.config.cjs"),
        File.join(root_dir, "tailwind.config.mjs"),
        File.join(root_dir, "tailwind.config.ts"),
        File.join(root_dir, "config"),
        File.join(root_dir, "styles.css"),
        File.join(root_dir, "src"),
        File.join(root_dir, "app"),
        File.join(root_dir, "assets")
      )
    end

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

      # Clean up
      client.stop
      expect(Dir.exist?(temp_dir)).to be false
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