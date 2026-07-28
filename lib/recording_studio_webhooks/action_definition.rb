# frozen_string_literal: true

# lib/recording_studio_webhooks/action_definition.rb
module RecordingStudioWebhooks
  class ActionDefinition
    NAME = /\A[a-z][a-z0-9_.:-]*\z/

    attr_reader :name, :implementation, :provider_name, :event_pattern, :priority, :policy_overrides,
      :source

    def initialize(name, implementation = nil, provider: nil, event: nil, priority: 100, policy: {}, source: nil, &block)
      @name = normalize_name(name)
      @implementation = implementation
      @provider_name = provider&.to_s&.downcase
      @event_pattern = EventPattern.new(event || name)
      @priority = Integer(priority)
      @policy_overrides = Policy.normalize_override(policy)
      instance_exec(self, &block) if block
      validate!
      @source = normalize_source(source)
      @policy_overrides = ImmutableSnapshot.build(@policy_overrides)
      @fingerprint = build_fingerprint
      freeze
    rescue ArgumentError, TypeError
      raise ConfigurationError, "action priority must be an integer"
    end

    def policy(value = nil, **options)
      @policy_overrides = Policy.normalize_override((value || {}).merge(options))
    end

    def handler(callable = nil, &block)
      @implementation = callable || block
    end

    def provider(value)
      @provider_name = value&.to_s&.downcase
    end

    def event(value)
      @event_pattern = EventPattern.new(value)
    end

    def matches?(provider, event_name)
      (provider_name.nil? || provider_name == provider.to_s.downcase) && event_pattern.matches?(event_name)
    end

    def sort_key
      kind, length = event_pattern.specificity
      [priority, -kind, -length, name]
    end

    def fingerprint = @fingerprint

    def build_fingerprint
      CanonicalJson.digest(
        name: name,
        provider: provider_name,
        event_pattern: event_pattern.value,
        priority: priority,
        source: source,
        implementation: implementation_name,
        policy: policy_overrides
      ).freeze
    end

    def snapshot
      ImmutableSnapshot.build(
        name: name,
        provider: provider_name,
        event_pattern: event_pattern.value,
        priority: priority,
        source: source,
        fingerprint: fingerprint,
        implementation: implementation_name,
        policy: policy_overrides
      )
    end

    private

    def normalize_name(value)
      name = value.to_s.downcase
      raise ConfigurationError, "action name is invalid" unless NAME.match?(name)

      name
    end

    def validate!
      unless provider_name.nil? || ProviderDefinition::NAME.match?(provider_name)
        raise ConfigurationError, "action provider is invalid"
      end
      raise ConfigurationError, "action handler is required" if implementation.nil?
    end

    def implementation_name
      implementation.respond_to?(:name) && !implementation.name.to_s.empty? ? implementation.name : "callable"
    end

    def normalize_source(value)
      source = value.nil? ? implementation_name : value.to_s.strip
      raise ConfigurationError, "action source is invalid" if source.empty? || source.bytesize > 255
      raise ConfigurationError, "action source must not contain secrets" if Redactor.secret_key?(source) || Redactor.secret_location?(source)

      source.freeze
    end
  end
end
