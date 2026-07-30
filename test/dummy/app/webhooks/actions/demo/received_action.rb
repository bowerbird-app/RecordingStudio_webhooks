# frozen_string_literal: true

module Webhooks
  module Actions
    module Demo
      class ReceivedAction < RecordingStudioWebhooks::Action
        def self.call(_context)
          true
        end

        def self.register!
          register(
            "demo.received",
            provider: "demo",
            event: "demo.received",
            policy: { max_retries: 0, redaction_keys: ["action_only"] }
          )
        end
      end
    end
  end
end

Webhooks::Actions::Demo::ReceivedAction.register!
