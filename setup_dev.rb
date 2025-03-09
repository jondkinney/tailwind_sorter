#!/usr/bin/env ruby
# frozen_string_literal: true

# This script sets up the gem for local development
require "fileutils"

puts "Setting up TailwindSorter for local development..."

# Install dependencies
system("bin/setup")

# Create binstubs
puts "Creating binstubs..."
system("bundle binstubs tailwind_sorter")

# Make binstubs executable
FileUtils.chmod("+x", ["bin/tailwind_sorter"])

puts "\nSetup complete! You can now run: bin/tailwind_sorter 'p-4 flex mt-2'"
