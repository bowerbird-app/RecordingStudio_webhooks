# frozen_string_literal: true

# lib/recording_studio_webhooks/errors.rb
module RecordingStudioWebhooks
  class Error < StandardError; end
  class ConfigurationError < Error; end
  class DuplicateRegistrationError < ConfigurationError; end
  class InvalidEventPatternError < ConfigurationError; end
  class InvalidPolicyError < ConfigurationError; end
  class UnsafeMetadataError < Error; end
end
