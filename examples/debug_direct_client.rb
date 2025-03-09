#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'tailwind_sorter'
require 'json'

puts "=== Debug Direct Client ==="
puts "This script tests the tailwindcss/sortClassList method from the language server"
puts

# Create a client and wrap its message sending/receiving with debug logging
client = TailwindSorter::DirectClient.new

# Monkey patch the client instance to add debug logging
def client.send_message(message)
  puts "\n→ Sending: #{JSON.pretty_generate(message)}"
  super
end

def client.read_message
  response = super
  puts "← Received: #{JSON.pretty_generate(response)}"
  response
end

# Test sorting some classes
classes = "p-4 flex mt-2"

puts "\nStarting client and testing with classes: #{classes}"
puts "=" * 80

begin
  # First get project info to see what the server detects
  project_info = client.get_project
  puts "\n\n\n\n\nProject information detected by Tailwind language server:\n"
  puts "-" * 57 + "\n"
  puts JSON.pretty_generate(project_info)
  puts "\n\n"
  
  # Try sorting the classes
  puts "\nTrying to sort classes...\n\n"
  sorted = client.sort_classes(classes)
  puts "\nResults:"
  puts "Original: #{classes}"
  puts "Sorted:   #{sorted}"
  
rescue => e
  puts "\n⚠️ ERROR: #{e.class}: #{e.message}"
  puts e.backtrace
ensure
  # Make sure to clean up
  client.stop
end
