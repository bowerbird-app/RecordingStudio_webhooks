# frozen_string_literal: true

# lib/recording_studio_webhooks/provider_definition.rb
module RecordingStudioWebhooks
  # Signature mode for a provider: a verifier, the built-in HMAC check, or an
  # explicit unsigned opt-out. Intake rejects a provider with none of these.
  module ProviderSignature
    def unsigned? = @unsigned == true

    def hmac_signature? = signature_verifier_callable.is_a?(HmacSignature)

    def signature_declared? = unsigned? || signature_verifier_configured?

    def unsigned(value = :__rsw_no_value__)
      return @unsigned if value == :__rsw_no_value__ || frozen?

      @unsigned = boolean_flag!(value, "unsigned")
    end

    def hmac_signature(signature_header: nil, timestamp_header: nil, tolerance: nil)
      return @signature_verifier if frozen?

      options = {}
      options[:signature_header] = signature_header if signature_header
      options[:timestamp_header] = timestamp_header if timestamp_header
      options[:tolerance] = tolerance if tolerance
      @signature_verifier = HmacSignature.new(**options)
    end

    private

    def validate_signature_mode!
      return unless unsigned? && signature_verifier_configured?

      raise ConfigurationError, "provider cannot be unsigned and use a signature check"
    end

    def boolean_flag!(value, label)
      return value if [true, false].include?(value)

      raise ConfigurationError, "#{label} must be true or false"
    end

    def assign_signature!(unsigned, signature_verifier, hmac)
      @unsigned = boolean_flag!(unsigned, "unsigned")
      @signature_verifier = signature_verifier
      return if hmac == false || hmac.nil?
      raise ConfigurationError, "provider cannot set hmac and a signature verifier" if @signature_verifier

      @signature_verifier = HmacSignature.from(hmac)
    end
  end

  class ProviderDefinition
    include ProviderSignature

    NAME = /\A[a-z][a-z0-9_-]*\z/

    attr_reader :name, :implementation, :policy_overrides, :event_policies,
      :event_type_extractor, :event_id_extractor, :source

    def initialize(name, implementation = nil, policy: {}, signature_verifier: nil,
      event_type_extractor: nil, event_id_extractor: nil, event_policies: {}, source: nil,
      unsigned: false, hmac: false, &block)
      @name = normalize_name(name)
      @implementation = implementation
      @policy_overrides = Policy.normalize_override(policy)
      @event_policies = PolicyResolver.normalize_event_policies(event_policies)
      assign_signature!(unsigned, signature_verifier, hmac)
      @event_type_extractor = event_type_extractor
      @event_id_extractor = event_id_extractor
      instance_exec(self, &block) if block
      validate_callables!
      validate_signature_mode!
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

    def signature_verifier_callable = @signature_verifier

    def event_type_extractor_callable = @event_type_extractor

    def event_id_extractor_callable = @event_id_extractor

    def signature_verifier_configured? = !@signature_verifier.nil?

    def event_type_extractor_configured? = !@event_type_extractor.nil?

    def event_id_extractor_configured? = !@event_id_extractor.nil?

    def signature_verifier(callable = :__rsw_no_value__, &block)
      return @signature_verifier if callable == :__rsw_no_value__ && !block_given?
      return @signature_verifier if frozen? && callable.nil? && !block_given?

      @signature_verifier = callable == :__rsw_no_value__ ? block : callable
    end

    def event_type(callable = :__rsw_no_value__, &block)
      return @event_type_extractor if callable == :__rsw_no_value__ && !block_given?
      return @event_type_extractor if frozen? && callable.nil? && !block_given?

      @event_type_extractor = callable == :__rsw_no_value__ ? block : callable
    end

    def event_id(callable = :__rsw_no_value__, &block)
      return @event_id_extractor if callable == :__rsw_no_value__ && !block_given?
      return @event_id_extractor if frozen? && callable.nil? && !block_given?

      @event_id_extractor = callable == :__rsw_no_value__ ? block : callable
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
