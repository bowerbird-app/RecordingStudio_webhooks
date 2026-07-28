# frozen_string_literal: true

# app/services/recording_studio_webhooks/inbound_intake.rb
module RecordingStudioWebhooks
  # Controller-independent public intake. The provider and endpoint identity in
  # the route identify the stable endpoint before its current credential is
  # checked.
  class InboundIntake
    SignatureContext = Struct.new(:raw_payload, :headers, :endpoint, :provider, keyword_init: true) do
      def inspect = "#<#{self.class.name} raw_payload=[FILTERED]>"
    end

    HookContext = Struct.new(:endpoint, :endpoint_token, :provider, :payload, :provenance, keyword_init: true)

    def self.call(...) = new(...).call

    def initialize(provider_name:, endpoint_identity:, token:, raw_payload: nil, payload: nil, content_type: nil, headers: {},
      request_metadata: {}, event_type: nil, provider_event_id: nil)
      @provider_name = provider_name.to_s.downcase
      @endpoint_identity = endpoint_identity.to_s.downcase
      @token = token
      @raw_payload = raw_payload.nil? ? payload : raw_payload
      @content_type = content_type
      @headers = headers
      @request_metadata = request_metadata
      @event_type = event_type
      @provider_event_id = provider_event_id
    end

    def call
      return failure(503, "recording_studio_unavailable") unless RecordingStudioGateway.available?

      provider = configuration.providers.fetch(@provider_name)
      return failure(404, "provider_unavailable") unless provider

      endpoint = Endpoint.find_by(provider_name: provider.name, identity_key: @endpoint_identity)
      return failure(404, "endpoint_unavailable") unless endpoint
      return failure(401, "endpoint_disabled") unless endpoint.enabled?

      endpoint_token = EndpointToken.authenticate(endpoint: endpoint, plaintext: @token)
      return failure(401, "token_invalid") unless endpoint_token
      return failure(415, "content_type_invalid") unless allowed_content_type?

      body = payload_string
      return failure(400, "payload_invalid") unless body
      return failure(413, "payload_too_large") if body.bytesize > configuration.max_payload_bytes
      return failure(401, "signature_invalid") unless signature_valid?(provider, body, endpoint)

      parsed_payload = parse_json(body)
      provenance = safe_provenance
      extraction_context = HookContext.new(
        endpoint: endpoint,
        endpoint_token: endpoint_token,
        provider: provider,
        payload: ImmutableSnapshot.build(Redactor.redact(parsed_payload, keys: configuration.secret_redaction_keys)),
        provenance: provenance
      )
      type = resolved_event_type(provider, parsed_payload, extraction_context)
      return failure(422, "event_type_invalid") unless valid_event_type?(type)

      resolution = PolicyResolver.resolve_event(
        configuration: configuration,
        provider: provider,
        endpoint: endpoint,
        event_type: type
      )
      context = HookContext.new(
        endpoint: endpoint,
        endpoint_token: endpoint_token,
        provider: provider,
        payload: ImmutableSnapshot.build(Redactor.redact(parsed_payload, keys: resolution.policy.redaction_keys)),
        provenance: provenance
      )
      return failure(429, "rate_limited") unless allowed_by_rate_limiter?(context)
      return failure(403, "not_authorized") unless authorized?(context)

      event_id = resolved_event_id(provider, parsed_payload, context)
      return failure(422, "provider_event_id_invalid") unless valid_event_id?(event_id)

      persisted_payload = Redactor.redact(
        parsed_payload,
        keys: persisted_redaction_keys(provider, endpoint, type, resolution)
      )

      persist_and_dispatch!(
        provider: provider,
        endpoint: endpoint,
        endpoint_token: endpoint_token,
        event_type: type,
        provider_event_id: event_id,
        deduplication_key: deduplication_key(event_id, parsed_payload, resolution),
        payload: persisted_payload,
        payload_digest: CanonicalJson.digest(parsed_payload),
        provenance: provenance,
        resolution: resolution
      )
    rescue JSON::ParserError
      failure(400, "json_invalid")
    rescue InvalidEventPatternError, InvalidPolicyError
      failure(422, "event_type_invalid")
    rescue StandardError
      # Do not expose request-derived values or exceptions from the public API.
      failure(503, "intake_unavailable")
    end

    def inspect = "#<#{self.class.name} request=[FILTERED]>"

    private

    def configuration = RecordingStudioWebhooks.configuration

    def payload_string
      return nil unless @raw_payload.respond_to?(:to_str)

      @raw_payload.to_str
    end

    def allowed_content_type?
      type = @content_type.to_s.split(";", 2).first.downcase.strip
      return false if type.empty?

      configuration.content_types.any? do |allowed|
        allowed == type || (allowed == "application/*+json" && /\Aapplication\/[a-z0-9.+-]+\+json\z/.match?(type))
      end
    end

    def signature_valid?(provider, body, endpoint)
      verifier = provider.signature_verifier
      return true unless verifier

      context = SignatureContext.new(
        raw_payload: body,
        headers: normalized_headers,
        endpoint: endpoint,
        provider: provider
      )
      invoke_signature_verifier(verifier, context)
    rescue StandardError
      false
    end

    def invoke_signature_verifier(verifier, context)
      if keyword_callable?(verifier)
        return invoke_keywords(
          verifier,
          raw_payload: context.raw_payload,
          payload: context.raw_payload,
          headers: context.headers,
          endpoint: context.endpoint,
          provider: context.provider,
          context: context
        ) == true
      end

      arity = verifier.respond_to?(:arity) ? verifier.arity : 1
      result =
        case arity
        when 1, -1 then verifier.call(context)
        when 2 then verifier.call(context.raw_payload, context.headers)
        else verifier.call(context.raw_payload, context.headers, context.endpoint)
        end
      result == true
    end

    def parse_json(body) = JSON.parse(body)

    def persisted_redaction_keys(provider, endpoint, event_type, resolution)
      action_policies = configuration.actions.matching(provider.name, event_type).map do |action|
        PolicyResolver.resolve_action(
          event_resolution: resolution,
          action: action,
          required_redaction_keys: configuration.secret_redaction_keys
        ).policy.redaction_keys
      end
      (resolution.policy.redaction_keys + action_policies.flatten).uniq.sort
    end

    def safe_provenance
      source = @request_metadata.respond_to?(:to_h) ? @request_metadata.to_h : {}
      source = {} unless source.respond_to?(:key?)
      configuration.provenance_keys.each_with_object({}) do |key, result|
        value = source.key?(key) ? source[key] : source[key.to_sym]
        next unless value.is_a?(String) || value.is_a?(Numeric) || value == true || value == false
        next if Redactor.secret_key?(key)

        result[key] = value.to_s.byteslice(0, 512)
      end
    end

    # Headers are transient verifier input only. They are never copied into a
    # log, provenance hash, Recording Studio event, or job payload.
    def normalized_headers
      source = @headers.respond_to?(:to_h) ? @headers.to_h : {}
      source.each_with_object({}) do |(key, value), result|
        next unless key.is_a?(String) || key.is_a?(Symbol)
        next unless value.is_a?(String) || value.is_a?(Numeric)

        result[key.to_s.downcase] = value.to_s.byteslice(0, 4_096)
      end
    end

    def allowed_by_rate_limiter?(context) = hook_allows?(configuration.rate_limiter, context)
    def authorized?(context) = hook_allows?(configuration.authorization_hook, context)

    def hook_allows?(hook, context)
      return true unless hook

      result = if keyword_callable?(hook)
        invoke_keywords(
          hook,
          context: context,
          endpoint: context.endpoint,
          endpoint_token: context.endpoint_token,
          provider: context.provider,
          payload: context.payload,
          provenance: context.provenance
        )
      elsif hook.respond_to?(:arity) && hook.arity == 2
        hook.call(context.endpoint, context)
      elsif hook.respond_to?(:arity) && hook.arity >= 3
        hook.call(context.endpoint, context.endpoint_token, context)
      else
        hook.call(context)
      end
      result.respond_to?(:success?) ? result.success? : result == true
    rescue StandardError
      false
    end

    def resolved_event_type(provider, payload, context)
      return @event_type.to_s unless @event_type.nil? || @event_type.to_s.empty?
      return invoke_extractor(provider.event_type_extractor, payload, context).to_s if provider.event_type_extractor

      payload["event_type"] || payload["type"] if payload.is_a?(Hash)
    end

    def resolved_event_id(provider, payload, context)
      value = if !@provider_event_id.nil? && !@provider_event_id.to_s.empty?
        @provider_event_id
      elsif provider.event_id_extractor
        invoke_extractor(provider.event_id_extractor, payload, context)
      elsif payload.is_a?(Hash)
        payload["event_id"] || payload["id"]
      end
      value&.to_s
    end

    def invoke_extractor(extractor, payload, context)
      return invoke_keywords(extractor, payload: payload, context: context, provider: context.provider) if keyword_callable?(extractor)

      extractor.respond_to?(:arity) && extractor.arity == 1 ? extractor.call(payload) : extractor.call(payload, context)
    end

    def valid_event_type?(value)
      EventPattern.validate_event_name!(value)
      true
    rescue InvalidEventPatternError
      false
    end

    def valid_event_id?(value)
      value.nil? || (value.is_a?(String) && !value.empty? && value.bytesize <= 255)
    end

    def deduplication_key(event_id, parsed_payload, resolution)
      return SecureRandom.uuid unless resolution.policy.deduplicate?

      return "event:#{event_id}" if event_id.present?

      "payload:#{CanonicalJson.digest(parsed_payload)}"
    end

    def persist_and_dispatch!(provider:, endpoint:, endpoint_token:, event_type:, provider_event_id:, deduplication_key:, payload:, payload_digest:, provenance:, resolution:)
      event = nil
      plans = []

      InboundEvent.transaction do
        event = InboundEvent.create!(
          endpoint: endpoint,
          endpoint_token: endpoint_token,
          provider_name: provider.name,
          event_type: event_type,
          provider_event_id: provider_event_id,
          payload_digest: payload_digest,
          deduplication_key: deduplication_key,
          payload: payload,
          provenance: provenance,
          endpoint_snapshot: endpoint.snapshot,
          token_snapshot: endpoint_token.snapshot,
          policy_snapshot: resolution.to_h,
          received_at: Time.current,
          status: "accepted"
        )
        plans = ActionPlanner.call(inbound_event: event, provider: provider, resolution: resolution)
        event.update!(status: "planned") if plans.any?
        endpoint.audit!(
          action: "recording_studio_webhooks.incoming.accepted",
          metadata: {
            inbound_event_id: event.id,
            provider: provider.name,
            event_type: event_type,
            provider_event_id: provider_event_id
          },
          idempotency_key: "recording_studio_webhooks:incoming:#{event.id}"
        )
      end

      plans.each { |plan| DispatchActionPlan.call(plan.id) }
      Result.new(status: 202, code: "accepted", record: event, details: { action_plan_count: plans.count })
    rescue ActiveRecord::RecordNotUnique
      existing = InboundEvent.find_by(endpoint_id: endpoint.id, deduplication_key: deduplication_key)
      return Result.new(status: 200, code: "duplicate", record: existing) if existing

      raise
    end

    def failure(status, code) = Result.new(status: status, code: code)

    def keyword_callable?(callable)
      callable.respond_to?(:parameters) && callable.parameters.any? { |kind, _| %i[key keyreq keyrest].include?(kind) }
    end

    def invoke_keywords(callable, values)
      parameters = callable.parameters
      return callable.call(**values) if parameters.any? { |kind, _| kind == :keyrest }

      accepted = parameters.filter_map { |kind, name| name if %i[key keyreq].include?(kind) }
      callable.call(**values.slice(*accepted))
    end
  end
end
