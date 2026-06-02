# frozen_string_literal: true

# Index of the `generated/types/` layer — required by the top-level barrel (`lib/dinie.rb`).
# Pure types: these files extend only `Dinie::Internal::Model` / `Dinie::Internal::OMIT` from
# the runtime (the controlled `generated → runtime` base import), never the transport. Ordered
# deps-first (the id/enum/money catalogs, then the models).

require_relative "types/ids"
require_relative "types/enums"
require_relative "types/money"
require_relative "types/credential"
require_relative "types/credit_offer"
require_relative "types/customer"
