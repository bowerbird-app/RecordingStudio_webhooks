# frozen_string_literal: true

# lib/recording_studio_webhooks/action.rb
module RecordingStudioWebhooks
  # Base class for action handlers that prefer class-based registration.
  class Action
    def self.register(name, **options, &)
      RecordingStudioWebhooks.register_action(name, self, **options, &)
    end
  end
end
