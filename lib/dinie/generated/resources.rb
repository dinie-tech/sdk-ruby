# frozen_string_literal: true

# Index of the `generated/resources/` layer — required by the top-level barrel (`lib/dinie.rb`).
# Resources hang off the shared {Dinie::Internal::HttpClient} the {Dinie::Client} owns; they import
# from `runtime/` (transport + paginator) and sibling `generated/` types, never the reverse
# (architecture §4). Hand-authored in V0.3, regenerated in V0.5.
#
# Each resource story appends its require here (additive): 007 customers; 008 credit_offers/loans;
# 010 banks/credentials/webhook_endpoints.

require_relative "resources/customers"
