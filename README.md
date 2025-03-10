# TailwindSorter

A Ruby gem that connects to a locally running TailwindCSS language server to sort space-separated CSS classes.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'tailwind_sorter'
```

And then execute:

```
$ bundle install
```

Or install it yourself as:

```
$ gem install tailwind_sorter
```

### JavaScript Dependencies

This gem relies on the official Tailwind CSS language server which is a Node.js package. The gem will automatically attempt to install and manage these dependencies when needed, but if you encounter any issues, you can install them manually or use the helper method:

```ruby
# Install dependencies through the gem helper
TailwindSorter.setup_dependencies

# Or manually with:
# yarn add @tailwindcss/language-server@^0.14.8 tailwindcss
# npm install @tailwindcss/language-server@^0.14.8 tailwindcss
```

## Usage

The gem will automatically detect your project's Tailwind configuration (if any) and use it for sorting classes.

```ruby
require 'tailwind_sorter'

# Sort your Tailwind CSS classes
unsorted_classes = "flex items-center justify-between py-4 px-6 bg-white"
sorted_classes = TailwindSorter.sort(unsorted_classes)
puts sorted_classes
# Output: "flex items-center justify-between bg-white px-6 py-4"
```

### Command Line Usage

The gem also provides a command-line tool:

```
$ tailwind_sorter "flex items-center justify-between py-4 px-6 bg-white"
# Output: flex items-center justify-between bg-white px-6 py-4
```

### Debugging

If you encounter any issues, you can enable debug mode:

```ruby
# In Ruby
TailwindSorter.debug = true
sorted = TailwindSorter.sort(classes)

# Or via command line
tailwind_sorter --debug "your classes here"
```

## Troubleshooting

If you encounter the error "Tailwind CSS language server not found", try:

1. Running `TailwindSorter.setup_dependencies` to install the JavaScript dependencies
2. Installing the JavaScript dependencies manually as described above
3. Checking if Node.js and npm/yarn are installed and accessible

## Setting Up In Your Application

If you're integrating this gem into an application, you might want to ensure the dependencies are installed during your application's setup process:

```ruby
# In a Rails initializer (config/initializers/tailwind_sorter.rb)
if defined?(Rails) && Rails.env.development?
  # Only attempt setup in development environment
  Rails.application.config.after_initialize do
    TailwindSorter.setup_dependencies(verbose: false)
  end
end
```

For non-Rails applications, you can run the setup anywhere in your application's initialization code:

```ruby
require 'tailwind_sorter'

# Check if dependencies are installed
TailwindSorter.setup_dependencies
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
