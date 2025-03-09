require_relative "lib/tailwind_sorter/version"

Gem::Specification.new do |spec|
  spec.name = "tailwind_sorter"
  spec.version = TailwindSorter::VERSION
  spec.authors = ["Your Name"]
  spec.email = ["your.email@example.com"]

  spec.summary = "Sort Tailwind CSS classes"
  spec.description = "A Ruby gem to sort Tailwind CSS classes using the Tailwind language server"
  spec.homepage = "https://github.com/yourusername/tailwind_sorter"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 2.6.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  # Specify which files should be added to the gem when it is released.
  spec.files = Dir["lib/**/*", "LICENSE.txt", "README.md"]
  spec.require_paths = ["lib"]

  spec.add_development_dependency "rspec", "~> 3.12"
  spec.add_development_dependency "rake", "~> 13.0"
end
