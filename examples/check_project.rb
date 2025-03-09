#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'tailwind_sorter'
require 'json'

puts "=== Tailwind Project Check ==="
puts "This script checks if the Tailwind language server can detect your project"
puts

# Use the direct client
TailwindSorter.use_direct_client = true

begin
  # Get project info
  project_info = TailwindSorter::DirectClient.new.get_project
  puts "Project information detected by Tailwind language server:"
  puts JSON.pretty_generate(project_info)
  
  # Try sorting a class string
  classes = "p-4 flex mt-2"
  puts "\nTrying to sort: #{classes}"
  sorted = TailwindSorter.sort(classes)
  puts "Sorted result: #{sorted}"
rescue => e
  puts "ERROR: #{e.class}: #{e.message}"
  puts e.backtrace
end