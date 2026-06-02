# frozen_string_literal: true

# Steep is informative (non-blocking) in v1 until the RBS surface stabilises
# (architecture §5.2, deferred decision §21.3 — promoted to a gate in story 013).
# At bootstrap `sig/` is a skeleton; gem/stdlib signatures arrive via RBS collection later.
target :lib do
  signature "sig"
  check "lib"

  # library "faraday"  # wired once an rbs_collection.yaml lands (story 013)
end
