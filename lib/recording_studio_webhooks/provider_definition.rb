# frozen_string_literal: true

# lib/recording_studio_webhooks/provider_definition.rb
module RecordingStudioWebhooks
  class ProviderDefinition
    NAME = /\A[a-z][a-z0-9_-]*\z/

    attr_reader :name, :implementation, :policy_overrides, :signature_verifier,
      :event_type_extractor, :event_id_extractor

    def initialize(name, implementation = nil, policy: {}, signature_verifier: nil,
      event_type_extractor: nil, event_id_extractor: nil, &block)
      @name = normalize_name(name)
      @implementation = implementation
      @policy_overrides = Policy.normalize_override(policy)
      @signature_verifier = signature_verifier
      @event_type_extractor = event_type_extractor
      @event_id_extractor = event_id_extractor
      instance_exec(self, &block) if block
      validate_callables!
      @policy_overrides = ImmutableSnapshot.build(@policy_overrides)
      freeze
    end

    def policy(value = nil, **options)
      @policy_overrides = Policy.normalize_override((value || {}).merge(options))
    end

    def signature_verifier(callable = nil, &block)
      @signature_verifier = callable || block
    end

    def event_type(callable = nil, &block)
      @event_type_extractor = callable || block
    end

    def event_id(callable = nil, &block)
      @event_id_extractor = callable || block
    end

    def snapshot
      ImmutableSnapshot.build(
        name: name,
        implementation: implementation_name,
        policy: policy_overrides
      )
    end

    private

    def normalize_name(value)
      name = value.to_s.downcase
      raise ConfigurationError, "provider name is invalid" unless NAME.match?(name)

      name
    end

    def validate_callables!
      [signature_verifier, event_type_extractor, event_id_extractor].compact.each do |callable|
        raise ConfigurationError, "provider callback must respond to call" unless callable.respond_to?(:call)
      end
    end

    def implementation_name
      implementation.respond_to?(:name) && !implementation.name.to_s.empty? ? implementation.name : "callable"
    end
  end
end
