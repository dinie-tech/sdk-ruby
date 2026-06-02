# dinie

Official Ruby SDK for the [Dinie](https://dinie.com.br) V3 API (backend-only).

> **Status — pre-release scaffold (`0.0.1`).** This is the bootstrap commit. The runtime
> (HTTP, OAuth2, retry, pagination, errors, webhooks, logger) and the generated resource
> layer land in stories 002+. The quickstart, end-to-end flow, and webhook sections below
> are skeletons filled in by the docs story (013).

## Requirements

- Ruby >= 3.1

## Installation

> Not yet published. `dinie` is a private gem; RubyGems publishing is planned for V1.0.

```ruby
# Gemfile (once published)
gem "dinie"
```

## Quickstart

_TODO (story 013)._

## End-to-end flow: Customer → Credit Offer → Loan

_TODO (story 013)._

## Webhooks

_TODO (story 013)._

## Development

```bash
bundle install
bundle exec rspec       # tests — WebMock, zero network
bundle exec rubocop     # lint
bundle exec steep check # type check — informative in v1
```

## License

[MIT](LICENSE) © Dinie
