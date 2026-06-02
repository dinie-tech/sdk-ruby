# frozen_string_literal: true

require "dinie"
require "webmock/rspec"

# Zero network is an invariant of the whole suite (architecture §14). WebMock blocks any
# real connection; runtime specs stub Faraday via WebMock from story 002 onward.
WebMock.disable_net_connect!

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed
end
