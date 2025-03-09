require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

task default: :spec

desc "Test sorting sample Tailwind CSS classes"
task :test_sort do |t, args|
  require_relative "lib/tailwind_sorter"

  classes = ENV["CLASSES"] || "p-4 flex mt-2"

  puts "Original: #{classes}"
  begin
    sorted = TailwindSorter.sort(classes)
    puts "Sorted:   #{sorted}"
  rescue TailwindSorter::Error => e
    puts "Error:    #{e.message}"
  end
end
