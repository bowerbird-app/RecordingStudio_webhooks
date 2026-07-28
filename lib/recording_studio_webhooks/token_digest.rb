# frozen_string_literal: true

# lib/recording_studio_webhooks/token_digest.rb
module RecordingStudioWebhooks
  module TokenDigest
    module_function

    def digest(token)
      value = token.to_s
      RecordingStudioWebhooks.configuration.digest_token(value)
    end

    def secure_compare(left, right)
      return false unless left.is_a?(String) && right.is_a?(String) && left.bytesize == right.bytesize

      ActiveSupport::SecurityUtils.secure_compare(left, right)
    end
  end
end
