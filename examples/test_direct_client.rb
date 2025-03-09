#!/usr/bin/env ruby
# frozen_string_literal: true

# Add the lib directory to the load path
$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

puts "Starting to load tailwind_sorter..."
# Now we can require the gem
require 'tailwind_sorter'
puts "Loaded tailwind_sorter successfully"

# Example classes to sort
examples = [
  "sm:p-2 p-4 flex mt-2",
  "text-red-500 p-4 flex items-center justify-between bg-white rounded-lg shadow-md hover:shadow-lg transition-all duration-300",
  "md:grid md:grid-cols-12 md:gap-8 container mx-auto px-4 py-8"
]

puts "Testing TailwindSorter with Direct Client...\n\n"

client = TailwindSorter::DirectClient.new
puts "Project Root: #{client.instance_variable_get(:@project_root)}"
puts "Config Path: #{client.instance_variable_get(:@config_path)}"
puts "\nProject Details... #{client.get_project}\n\n"

examples.each do |classes|
  puts "Original: #{classes}"
  sorted = client.sort_classes(classes)
  puts "Sorted:   #{sorted}"
  puts "-" * 80
end

puts "Done!"
