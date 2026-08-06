# frozen_string_literal: true

module Webhooks
  module Providers
    class Stripe < RecordingStudioWebhooks::Provider
      def self.register!
        register(
          "stripe",
          signature_verifier: ->(_context) { true },
          event_type_extractor: ->(payload) { payload["type"] },
          event_id_extractor: ->(payload) { payload["id"] }
        )
      end
    end
  end
end

Webhooks::Providers::Stripe.register!
