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

## Usage

First, make sure the Tailwind CSS language server is running locally.

```ruby
require 'tailwind_sorter'

# Sort your Tailwind CSS classes
unsorted_classes = "flex items-center justify-between py-4 px-6 bg-white"
sorted_classes = TailwindSorter.sort(unsorted_classes)
puts sorted_classes
# Output might be: "flex items-center justify-between bg-white px-6 py-4"
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
