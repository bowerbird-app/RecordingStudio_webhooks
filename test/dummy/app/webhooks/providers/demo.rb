# frozen_string_literal: true

module Webhooks
  module Providers
    class Demo < RecordingStudioWebhooks::Provider
      def self.register!
        register(
          "demo",
          event_type_extractor: ->(payload) { payload["type"] },
          event_id_extractor: ->(payload) { payload["id"] }
        )
      end
    end
  end
end

Webhooks::Providers::Demo.register!
