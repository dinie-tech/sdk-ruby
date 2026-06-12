# frozen_string_literal: true

require_relative "lib/dinie/version"

Gem::Specification.new do |spec|
  spec.name = "dinie-sdk"
  spec.version = Dinie::VERSION
  spec.authors = ["Dinie"]
  spec.email = ["engineering@dinie.com.br"]

  spec.summary = "Official Ruby SDK for the Dinie V3 API (backend-only)."
  spec.description = "Hand-written Ruby SDK for the Dinie V3 API: OAuth2 client-credentials auth, " \
                     "automatic retries, cursor pagination, typed errors, and webhook verification."
  spec.homepage = "https://dinie.com.br"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/dinie-tech/sdk-ruby"
  spec.metadata["changelog_uri"] = "https://github.com/dinie-tech/sdk-ruby/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"
  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["api_version"] = "2026-03-01"

  spec.files = Dir.glob("lib/**/*.rb") + Dir.glob("sig/**/*.rbs") + %w[README.md LICENSE CHANGELOG.md]
  spec.require_paths = ["lib"]

  # Runtime dependencies (ubiquitous; architecture §19). Faraday 2.x extracted its adapters into
  # separate gems, so the `:net_http_persistent` adapter (real connection pool + keep-alive,
  # architecture §10/RB15) ships as `faraday-net_http_persistent`, which depends on the underlying
  # `net-http-persistent`. The latter stays pinned explicitly so the pool gem's major is fixed.
  spec.add_dependency "faraday", "~> 2.0"
  spec.add_dependency "faraday-multipart", "~> 1.0"
  spec.add_dependency "faraday-net_http_persistent", "~> 2.0"
  spec.add_dependency "net-http-persistent", "~> 4.0"
  # Formerly-default stdlib gems the runtime requires directly. `base64` left the default gems in
  # Ruby 3.4 and `logger` in 3.5, so they must be declared or `require "dinie"` breaks on Ruby ≥3.4
  # (`required_ruby_version >= 3.1`). See lib/dinie/runtime/{token_manager,logger}.rb.
  spec.add_dependency "base64", "~> 0.2"
  spec.add_dependency "logger", "~> 1.6"

  # Development dependencies (declared here; see `.rubocop.yml` Gemspec/DevelopmentDependencies).
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rbs", "~> 3.4"
  spec.add_development_dependency "rspec", "~> 3.13"
  spec.add_development_dependency "rubocop", "~> 1.60"
  spec.add_development_dependency "steep", "~> 1.6"
  spec.add_development_dependency "webmock", "~> 3.19"
  spec.add_development_dependency "yard", "~> 0.9"
end
