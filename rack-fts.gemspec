# frozen_string_literal: true

require_relative "lib/rack/fts/version"

Gem::Specification.new do |spec|
  spec.name = "rack-fts"
  spec.version = Rack::FTS::VERSION
  spec.authors = ["Rack-FTS Contributors"]
  spec.email = ["info@example.com"]

  spec.summary = "Functional Task Supervisor for Rack applications"
  spec.description = "A Ruby gem implementing multi-stage task lifecycle (Authenticate, Authorize, Action, Render) using dry-monads for Rack and Rails applications"
  spec.homepage = "https://github.com/example/rack-fts"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3.6"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z 2>/dev/null`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end
  
  spec.files += Dir["lib/**/*.rb"]
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Runtime dependencies
  spec.add_dependency "rack", "~> 3.0"
  spec.add_dependency "dry-monads", "~> 1.6"
  spec.add_dependency "dry-configurable", "~> 1.0"

  # Development dependencies
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.12"
  spec.add_development_dependency "cucumber", "~> 9.0"
  spec.add_development_dependency "rack-test", "~> 2.1"
  spec.add_development_dependency "rubocop", "~> 1.50"
  spec.add_development_dependency "rubocop-rspec", "~> 2.20"
  spec.add_development_dependency "simplecov", "~> 0.22"
  
  # Optional Rails support
  # spec.add_development_dependency "rails", "~> 8.0"
end
