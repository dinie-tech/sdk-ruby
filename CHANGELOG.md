# Changelog

All notable changes to the `dinie-sdk` gem are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.1.1] - 2026-11-06

### Fixed
- The default `base_url` is now `https://api.dinie.com/api/v3`. The previous default,
  `https://api.dinie.com.br/api/v3`, does not resolve, so a client built without a `base_url`
  could not reach the API.

## [1.1.0] - 2026-06-13

## [1.0.1] — 2026-06-12

### Fixed
- Declare `base64` and `logger` as runtime dependencies. Both left Ruby's default gems
  (`base64` in 3.4, `logger` in 3.5) and are required directly by the runtime, so `require "dinie"`
  raised `LoadError: cannot load such file -- base64` on Ruby ≥3.4 (the gem supports `>= 3.1`).

## [1.0.0] — 2026-06-12

Initial public release.
