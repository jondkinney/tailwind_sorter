require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

task default: :spec

desc "Test sorting sample Tailwind CSS classes"
task :test_sort do |t, args|
  require "bundler/setup"
  require_relative "lib/tailwind_sorter"

  TailwindSorter.debug = ENV["DEBUG"] == "true"
  classes = ENV["CLASSES"] || "p-4 flex mt-2"

  puts "Original: #{classes}"
  begin
    sorted = TailwindSorter.sort(classes)
    puts "Sorted:   #{sorted}"
  rescue TailwindSorter::Error => e
    puts "Error:    #{e.message}"
  ensure
    # Clean up resources
    TailwindSorter.stop_server if defined?(TailwindSorter.stop_server)
  end
end

desc "Install JavaScript dependencies required by this gem"
task :install_js_deps do
  require "json"

  package_json_path = File.join(__dir__, 'package.json')
  if File.exist?(package_json_path)
    pkg_data = JSON.parse(File.read(package_json_path))
    puts "Installing JavaScript dependencies for #{pkg_data['name']} gem..."

    # Determine which package manager to use
    if system('which yarn > /dev/null 2>&1')
      puts "Using yarn..."
      system('yarn install') || abort("Failed to install dependencies with yarn")
    elsif system('which npm > /dev/null 2>&1')
      puts "Using npm..."
      system('npm install') || abort("Failed to install dependencies with npm")
    else
      abort("Neither yarn nor npm found. Please install one of them to use this gem.")
    end

    # Verify installation
    ls_path = File.join(__dir__, 'node_modules', '.bin', 'tailwindcss-language-server')
    if File.exist?(ls_path)
      puts "Successfully installed JavaScript dependencies!"
    else
      abort("Failed to install tailwindcss-language-server. Try installing manually with: yarn add @tailwindcss/language-server tailwindcss")
    end
  else
    abort("package.json not found. The gem appears to be improperly installed.")
  end
end

# Make install:local also install JavaScript dependencies
task 'install:local' => :install_js_deps
