# frozen_string_literal: true

module Webhooks
  module Providers
    class Demo < RecordingStudioWebhooks::Provider
      def self.register!
        register(
          "demo",
          # Local stand-in so seeds, the tester, and sample pages keep working.
          # Hosts use hmac_signature or their own verifier.
          signature_verifier: ->(_context) { true },
          event_type_extractor: ->(payload) { payload["type"] },
          event_id_extractor: ->(payload) { payload["id"] }
        )
      end
    end
  end
end

Webhooks::Providers::Demo.register!
