# frozen_string_literal: true

# lib/recording_studio_webhooks/provider_definition.rb
module RecordingStudioWebhooks
  class ProviderDefinition
    NAME = /\A[a-z][a-z0-9_-]*\z/

    attr_reader :name, :implementation, :policy_overrides, :event_policies, :signature_verifier,
      :event_type_extractor, :event_id_extractor, :source

    def initialize(name, implementation = nil, policy: {}, signature_verifier: nil,
      event_type_extractor: nil, event_id_extractor: nil, event_policies: {}, source: nil, &block)
      @name = normalize_name(name)
      @implementation = implementation
      @policy_overrides = Policy.normalize_override(policy)
      @event_policies = PolicyResolver.normalize_event_policies(event_policies)
      @signature_verifier = signature_verifier
      @event_type_extractor = event_type_extractor
      @event_id_extractor = event_id_extractor
      instance_exec(self, &block) if block
      validate_callables!
      @source = normalize_source(source)
      @policy_overrides = ImmutableSnapshot.build(@policy_overrides)
      @event_policies = ImmutableSnapshot.build(@event_policies)
      @fingerprint = build_fingerprint
      freeze
    end

    def policy(value = nil, **options)
      @policy_overrides = Policy.normalize_override((value || {}).merge(options))
    end

    def event_policy(pattern, value = nil, **options)
      rules = Array(@event_policies).map { |rule| rule.dup }
      rules << {
        "pattern" => pattern,
        "policy" => (value || {}).merge(options)
      }
      @event_policies = PolicyResolver.normalize_event_policies(rules)
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
        source: source,
        fingerprint: fingerprint,
        policy: policy_overrides,
        event_policies: event_policies
      )
    end

    def fingerprint = @fingerprint

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

    def normalize_source(value)
      source = value.nil? ? implementation_name : value.to_s.strip
      raise ConfigurationError, "provider source is invalid" if source.empty? || source.bytesize > 255
      raise ConfigurationError, "provider source must not contain secrets" if Redactor.secret_key?(source) || Redactor.secret_location?(source)

      source.freeze
    end

    def build_fingerprint
      CanonicalJson.digest(
        name: name,
        implementation: implementation_name,
        source: source,
        policy: policy_overrides,
        event_policies: event_policies
      ).freeze
    end
  end
end
