# frozen_string_literal: true

# lib/recording_studio_webhooks/provider.rb
module RecordingStudioWebhooks
  # Base class for providers that prefer class-based registration.
  class Provider
    def self.register(name, **options, &)
      RecordingStudioWebhooks.register_provider(name, self, **options, &)
    end
  end
end
