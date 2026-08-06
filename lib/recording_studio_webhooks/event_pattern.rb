# frozen_string_literal: true

# lib/recording_studio_webhooks/event_pattern.rb
module RecordingStudioWebhooks
  # Event patterns are deliberately narrow. A wildcard may only appear as a
  # suffix after a dot, e.g. "invoice.*" matches "invoice.paid" and
  # "invoice.payment.failed". `*` is the only catch-all. It is not a
  # general glob language.
  class EventPattern
    SEGMENT = "[A-Za-z0-9][A-Za-z0-9_:-]*"
    EVENT = /\A#{SEGMENT}(?:\.#{SEGMENT})*\z/
    WILDCARD = /\A(#{SEGMENT}(?:\.#{SEGMENT})*)\.\*\z/

    attr_reader :value

    def initialize(value)
      @value = value.to_s
      raise InvalidEventPatternError, "event pattern is invalid" unless self.class.valid_pattern?(@value)

      freeze
    end

    def exact? = !wildcard?

    def wildcard? = catch_all? || value.end_with?(".*")

    def catch_all? = value == "*"

    def matches?(event_name)
      event = self.class.validate_event_name!(event_name)
      return true if catch_all?
      return event == value if exact?

      prefix = value.delete_suffix(".*")
      event.start_with?("#{prefix}.")
    end

    # Exact patterns are most specific, suffix wildcards next, and `*` last.
    def specificity
      return [2, value.length] if exact?
      return [0, 0] if catch_all?

      [1, value.delete_suffix(".*").length]
    end

    def self.validate_event_name!(value)
      event = value.to_s
      raise InvalidEventPatternError, "event name is invalid" unless EVENT.match?(event)

      event
    end

    def self.valid_pattern?(value)
      value == "*" || EVENT.match?(value) || WILDCARD.match?(value)
    end
  end
end
