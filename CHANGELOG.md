# Changelog

All notable changes to the `dinie` gem are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Project scaffold: `dinie.gemspec` (private gem, Ruby >= 3.1; `faraday ~> 2.0` +
  `net-http-persistent ~> 4.0`), `Gemfile`, `Rakefile`.
- `lib/dinie.rb` deterministic barrel (explicit `require_relative`, no Zeitwerk) and
  `lib/dinie/version.rb` (`Dinie::VERSION`).
- `lib/dinie/runtime/` <-> `lib/dinie/generated/` directory boundary with `CODEOWNERS`
  (human-owned runtime, bot-owned generated layer — architecture §4.2).
- RSpec + WebMock (zero network) test tree with a `Dinie::VERSION` smoke spec.
- RuboCop config, RBS `sig/` skeleton + `Steepfile`, YARD `.yardopts`.
- CI workflow: `bundle install` -> RuboCop -> RSpec -> Steep (informative) on Ruby
  3.1, 3.2, 3.3.
- `.env.example` for the deferred (non-gate) live smoke E2E.
