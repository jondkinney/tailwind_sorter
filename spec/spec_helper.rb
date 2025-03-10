require 'bundler/setup'

# Set test environment
ENV['RAILS_ENV'] = 'test'
ENV['RACK_ENV'] = 'test'

require 'tailwind_sorter'
require_relative 'support/file_helpers'

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = "spec/examples.txt"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Include the FileHelpers module in all test files
  config.include FileHelpers

  # Run tests in random order
  config.order = :random
  Kernel.srand config.seed
end
