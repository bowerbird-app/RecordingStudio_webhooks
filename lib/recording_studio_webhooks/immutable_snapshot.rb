# frozen_string_literal: true

# lib/recording_studio_webhooks/immutable_snapshot.rb
module RecordingStudioWebhooks
  # Builds JSON-compatible values which callers cannot mutate accidentally.
  module ImmutableSnapshot
    module_function

    def build(value)
      freeze_value(normalize(value))
    end

    def normalize(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, item), normalized|
          normalized[key.to_s] = normalize(item)
        end
      when Array
        value.map { |item| normalize(item) }
      when Time, Date, DateTime
        value.iso8601(6)
      when String
        value.dup
      when Symbol
        value.to_s
      when Numeric, TrueClass, FalseClass, NilClass
        value
      else
        value.to_s
      end
    end

    def freeze_value(value)
      case value
      when Hash
        value.each_value { |item| freeze_value(item) }
      when Array
        value.each { |item| freeze_value(item) }
      when String
        value.freeze
      end
      value.freeze
    end
    private_class_method :freeze_value
  end
end
