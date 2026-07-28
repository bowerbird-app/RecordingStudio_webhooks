# frozen_string_literal: true

# lib/recording_studio_webhooks/action_definition.rb
module RecordingStudioWebhooks
  class ActionDefinition
    NAME = /\A[a-z][a-z0-9_.:-]*\z/

    attr_reader :name, :implementation, :provider_name, :event_pattern, :priority, :policy_overrides

    def initialize(name, implementation = nil, provider: nil, event: nil, priority: 100, policy: {}, &block)
      @name = normalize_name(name)
      @implementation = implementation
      @provider_name = provider&.to_s&.downcase
      @event_pattern = EventPattern.new(event || name)
      @priority = Integer(priority)
      @policy_overrides = Policy.normalize_override(policy)
      instance_exec(self, &block) if block
      validate!
      @policy_overrides = ImmutableSnapshot.build(@policy_overrides)
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
      exact, length = event_pattern.specificity
      [-exact, -length, priority, name]
    end

    def snapshot
      ImmutableSnapshot.build(
        name: name,
        provider: provider_name,
        event_pattern: event_pattern.value,
        priority: priority,
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
  end
end
