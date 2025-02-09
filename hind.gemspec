require_relative 'lib/hind/version'

Gem::Specification.new do |spec|
  spec.name          = "hind"
  spec.version       = Hind::VERSION
  spec.authors       = ["Aboobacker MK"]
  spec.email         = ["aboobackervyd@gmail.com"]

  spec.summary       = "LSIF and SCIP generator for Ruby"
  spec.description   = "A tool to generate LSIF and SCIP index files for Ruby codebases"
  spec.homepage      = "https://github.com/tachyons/hind"
  spec.license       = "MIT"
  spec.required_ruby_version = Gem::Requirement.new(">= 2.7.0")

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  spec.files = Dir["lib/**/*", "bin/*", "README.md", "LICENSE.txt"]
  spec.bindir        = "bin"
  spec.executables   = ["hind"]
  spec.require_paths = ["lib"]

  spec.add_dependency "prism", "~> 0.19.0"
  spec.add_dependency "thor", "~> 1.2"
  spec.add_dependency "zeitwerk", "~> 2.6"

  spec.add_development_dependency "bundler", "~> 2.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.0"
end
