# frozen_string_literal: true

# lib/recording_studio_webhooks/errors.rb
module RecordingStudioWebhooks
  class Error < StandardError; end
  class ConfigurationError < Error; end
  class DuplicateRegistrationError < ConfigurationError; end
  class InvalidEventPatternError < ConfigurationError; end
  class InvalidPolicyError < ConfigurationError; end
  class UnsafeMetadataError < Error; end
  class RecordingStudioUnavailableError < Error; end
  class RecordingStudioConfigurationError < Error; end
  class TokenIdentityConflictError < Error; end

  # NameError covers NoMethodError. Host callbacks may still raise other
  # StandardError subclasses; public intake and action execution catch those.
  HOST_CALLBACK_ERRORS = [
    ArgumentError,
    TypeError,
    NameError,
    KeyError,
    RuntimeError,
    Error
  ].freeze

  def self.log_fail_closed(error, context:)
    message = "[recording_studio_webhooks] #{context}: #{error.class}: #{error.message}"
    logger = defined?(Rails) && Rails.respond_to?(:logger) ? Rails.logger : nil
    logger&.warn(message)
  end
end
