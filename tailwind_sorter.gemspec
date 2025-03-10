require_relative "lib/tailwind_sorter/version"

Gem::Specification.new do |spec|
  spec.name = "tailwind_sorter"
  spec.version = TailwindSorter::VERSION
  spec.authors = ["Jon Kinney"]
  spec.email = ["jonkinney@gmail.com"]

  spec.summary = "A tool to sort Tailwind CSS classes using the official Tailwind CSS language server"
  spec.description = "Provides both a Ruby API and command-line tool to sort Tailwind CSS classes in the same order as the official Tailwind CSS IntelliSense plugin"
  spec.homepage = "https://github.com/jondkinney/tailwind_sorter"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 2.6.0"

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "source_code_uri" => spec.homepage,
    "changelog_uri" => "#{spec.homepage}/blob/main/CHANGELOG.md"
  }

  # Specify which files should be added to the gem when it is released.
  spec.files = Dir[
    "lib/**/*",
    "bin/*",
    "README.md",
    "LICENSE.txt",
    "CHANGELOG.md"
  ]
  spec.bindir = "bin"
  spec.executables = ["tailwind_sorter", "tailwind_server"]
  spec.require_paths = ["lib"]

  # Runtime dependencies
  spec.add_dependency "json"

  # Development dependencies
  spec.add_development_dependency "bundler", "~> 2.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.12"
end
