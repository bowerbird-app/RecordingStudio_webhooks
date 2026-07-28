# frozen_string_literal: true

# lib/recording_studio_webhooks/redactor.rb
module RecordingStudioWebhooks
  module Redactor
    FILTERED = "[FILTERED]"
    SECRET_KEY = /(?:authorization|credential|pass(?:word)?|secret|signature|token|api[_-]?key)/i

    module_function

    def redact(value, keys:)
      normalized_keys = Array(keys).map { |key| key.to_s.downcase }.to_set
      redact_value(value, normalized_keys)
    end

    def secret_key?(key)
      SECRET_KEY.match?(key.to_s)
    end

    def redact_value(value, keys)
      case value
      when Hash
        value.each_with_object({}) do |(key, item), redacted|
          name = key.to_s
          redacted[name] = keys.include?(name.downcase) || secret_key?(name) ? FILTERED : redact_value(item, keys)
        end
      when Array
        value.map { |item| redact_value(item, keys) }
      when String
        value.dup
      when Numeric, TrueClass, FalseClass, NilClass
        value
      else
        FILTERED
      end
    end
    private_class_method :redact_value
  end
end
