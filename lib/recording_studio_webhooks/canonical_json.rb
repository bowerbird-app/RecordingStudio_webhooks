# frozen_string_literal: true

# lib/recording_studio_webhooks/canonical_json.rb
module RecordingStudioWebhooks
  module CanonicalJson
    module_function

    def dump(value)
      JSON.generate(canonicalize(value))
    end

    def digest(value)
      OpenSSL::Digest::SHA256.hexdigest(dump(value))
    end

    def canonicalize(value)
      case value
      when Hash
        value.keys.map(&:to_s).sort.each_with_object({}) do |key, result|
          source_key = value.key?(key) ? key : value.keys.find { |candidate| candidate.to_s == key }
          result[key] = canonicalize(value.fetch(source_key))
        end
      when Array
        value.map { |item| canonicalize(item) }
      when Numeric, String, TrueClass, FalseClass, NilClass
        value
      else
        raise ArgumentError, "payload is not JSON-compatible"
      end
    end
  end
end
