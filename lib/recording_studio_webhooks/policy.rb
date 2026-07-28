# frozen_string_literal: true

# lib/recording_studio_webhooks/policy.rb
module RecordingStudioWebhooks
  # Policy values are snapshot-friendly and immutable. nil means
  # "unspecified" in an override. Precedence belongs to PolicyResolver, not to
  # this value object.
  class Policy
    EXECUTION_MODES = %w[independent sequential].freeze
    KEYS = %i[
      enabled
      execution_mode
      max_retries
      retry_backoff
      max_retry_backoff
      redaction_keys
      deduplicate
    ].freeze
    DEFAULT_VALUES = {
      "enabled" => true,
      "execution_mode" => "independent",
      "max_retries" => 3,
      "retry_backoff" => 5,
      "max_retry_backoff" => 300,
      "redaction_keys" => [],
      "deduplicate" => true
    }.freeze

    attr_reader :values

    def initialize(values)
      @values = ImmutableSnapshot.build(validate!(values))
      freeze
    end

    def enabled? = values.fetch("enabled")

    def execution_mode = values.fetch("execution_mode")

    def sequential? = execution_mode == "sequential"

    def max_retries = values.fetch("max_retries")

    def retry_backoff = values.fetch("retry_backoff")

    def max_retry_backoff = values.fetch("max_retry_backoff")

    def redaction_keys = values.fetch("redaction_keys")

    def deduplicate? = values.fetch("deduplicate")

    def to_h = values

    def self.default
      new(DEFAULT_VALUES)
    end

    def self.normalize_override(value)
      hash = value.respond_to?(:to_h) ? value.to_h : value
      raise InvalidPolicyError, "policy must be a hash" unless hash.is_a?(Hash)

      hash.each_with_object({}) do |(key, item), normalized|
        name = key.to_sym
        raise InvalidPolicyError, "unknown policy option" unless KEYS.include?(name)
        next if item.nil?

        normalized[name.to_s] = item
      end
    end

    def self.valid_override?(value)
      normalize_override(value)
      true
    rescue InvalidPolicyError
      false
    end

    # The public policy API keeps precedence explicit: endpoint overrides win,
    # followed by action, provider, and the configured default. Redaction keys
    # are additive so a narrower scope cannot make a required filter disappear.
    def self.resolve(default:, provider: {}, action: {}, endpoint: {}, required_redaction_keys: [])
      default_values = default.respond_to?(:to_h) ? default.to_h : default
      values = DEFAULT_VALUES
        .merge(normalize_override(default_values))
        .merge(normalize_override(provider || {}))
        .merge(normalize_override(action || {}))
        .merge(normalize_override(endpoint || {}))
      values["redaction_keys"] = (Array(required_redaction_keys) + Array(values["redaction_keys"]))
        .map { |key| key.to_s.downcase }
        .uniq
        .sort
      new(values)
    end

    private

    def validate!(input)
      values = DEFAULT_VALUES.merge(self.class.normalize_override(input))

      raise InvalidPolicyError, "enabled must be boolean" unless boolean?(values["enabled"])
      raise InvalidPolicyError, "deduplicate must be boolean" unless boolean?(values["deduplicate"])

      mode = values["execution_mode"].to_s
      raise InvalidPolicyError, "execution mode is invalid" unless EXECUTION_MODES.include?(mode)
      values["execution_mode"] = mode

      %w[max_retries retry_backoff max_retry_backoff].each do |key|
        values[key] = Integer(values[key])
        raise InvalidPolicyError, "#{key} must be non-negative" if values[key].negative?
      rescue ArgumentError, TypeError
        raise InvalidPolicyError, "#{key} must be an integer"
      end

      raise InvalidPolicyError, "max retries is too large" if values["max_retries"] > 20
      raise InvalidPolicyError, "retry backoff must be positive" if values["retry_backoff"].zero?
      raise InvalidPolicyError, "max retry backoff must be positive" if values["max_retry_backoff"].zero?

      keys = Array(values["redaction_keys"])
      raise InvalidPolicyError, "redaction keys must be strings" unless keys.all? { |key| key.is_a?(String) || key.is_a?(Symbol) }

      values["redaction_keys"] = keys.map { |key| key.to_s.downcase }.uniq.sort
      values
    end

    def boolean?(value)
      value == true || value == false
    end

  end
end
