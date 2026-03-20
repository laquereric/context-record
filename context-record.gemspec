# frozen_string_literal: true

require_relative "lib/context_record/version"

Gem::Specification.new do |spec|
  spec.name = "context-record"
  spec.version = ContextRecord::VERSION
  spec.authors = ["Dick Dowdell"]
  spec.summary = "Typed JSON-LD message envelope and primitive for deterministic LLM input"
  spec.description = <<~DESC
    Provides ContextRecord::Record (immutable self-describing message envelope)
    and ContextRecord::ContextPrimitive (typed JSON-LD node with deterministic
    serialization). Identical inputs produce byte-identical JSON-LD payloads,
    enabling repeatable LLM responses.
  DESC
  spec.homepage = "https://github.com/laquereric/context-record"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["github_repo"] = "ssh://github.com/laquereric/context-record"

  spec.files = Dir.chdir(__dir__) do
    Dir["{lib}/**/*", "LICENSE.txt", "README.md", "VERSION"]
  end

  spec.require_paths = ["lib"]

  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "rake", "~> 13.0"
end
