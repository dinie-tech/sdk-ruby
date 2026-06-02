# frozen_string_literal: true

# Index of the `generated/events/` layer — required by the top-level barrel (`lib/dinie.rb`).
# The 15 typed webhook events (`Dinie::Events::*`), the shared {Dinie::Events::WebhookEventBase}
# envelope, and the {Dinie::Events::DESERIALIZERS} dispatch table (architecture §3.1, §4.1, §8).
# Hand-authored in V0.3 (the second hotspot); regenerated in V0.5. Pure generated types: these
# files extend only `Dinie::Internal::Model` from the runtime (the controlled `generated → runtime`
# base import) and reuse {Dinie::Kyc.deserialize_requirement} for embedded KYC requirements.
#
# Ordered deps-first: the envelope base, then `deserializers.rb` (which requires all 15 member
# files before building the frozen dispatch table). `runtime/webhooks.rb` consumes
# {Dinie::Events::DESERIALIZERS} via the controlled inverse import (forcing-function, §4).

require_relative "events/base"
require_relative "events/deserializers"
