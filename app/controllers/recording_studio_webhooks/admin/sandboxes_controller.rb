# frozen_string_literal: true

require "ostruct"

module RecordingStudioWebhooks
  module Admin
    class SandboxesController < BaseController
      before_action :load_endpoint_from_params
      before_action :load_provider_options

      def show
        return unless @endpoint

        @selected_provider_name = @endpoint.provider_name
      end

      def create
        raw_payload = sandbox_fields.fetch(:payload, "").to_s
        raise ArgumentError if raw_payload.bytesize > webhook_configuration.max_payload_bytes

        payload = JSON.parse(raw_payload)
        headers = parsed_headers
        @selected_provider_name = resolved_provider_name
        provider = webhook_configuration.providers.fetch(@selected_provider_name)
        raise ArgumentError unless provider

        event_type = resolved_event_type(provider, payload)
        EventPattern.validate_event_name!(event_type)

        @sandbox_result = build_sandbox_result(provider, payload, event_type, headers)
        render :show
      rescue ArgumentError, JSON::ParserError, InvalidEventPatternError
        @form_error = "Provide a JSON payload and a valid event type."
        render :show, status: :unprocessable_entity
      end

      private

      def sandbox_fields
        params.require(:sandbox).permit(:provider_name, :endpoint_id, :event_type, :headers_json, :payload)
      end

      def build_sandbox_result(provider, payload, event_type, headers)
        endpoint = @endpoint || endpoint_scope.where(provider_name: provider.name).order(created_at: :desc).first
        event_endpoint = endpoint || OpenStruct.new(policy_overrides: {}, provider_name: provider.name,
                                                    recording_studio_recording_id: "n/a", label: "n/a")
        actions = webhook_configuration.actions.matching(provider.name, event_type)
        event_resolution = PolicyResolver.resolve_event(
          configuration: webhook_configuration,
          provider: provider,
          endpoint: event_endpoint,
          event_type: event_type
        )
        resolutions = actions.map do |action|
          PolicyResolver.resolve_action(
            event_resolution: event_resolution,
            action: action,
            required_redaction_keys: webhook_configuration.secret_redaction_keys
          )
        end
        redaction_keys = (
          [event_resolution.policy.redaction_keys] +
          resolutions.map { |resolution| resolution.policy.redaction_keys }
        ).flatten

        ImmutableSnapshot.build(
          event_type: event_type,
          payload: Redactor.redact(payload, keys: redaction_keys),
          actions: actions.zip(resolutions).map do |action, resolution|
            policy = resolution.policy
            {
              name: action.name,
              event_pattern: action.event_pattern.value,
              enabled: policy.enabled?,
              execution_mode: policy.execution_mode,
              max_retries: policy.max_retries,
              source: resolution.source,
              policy_fingerprint: resolution.fingerprint
            }
          end
        ).merge(
          "provider" => provider.snapshot,
          "dispatcher" => dispatcher_name,
          "checks" => build_checks(provider: provider, endpoint: endpoint, headers: headers, payload: payload,
                                   event_type: event_type)
        )
      end

      def build_checks(provider:, endpoint:, headers:, payload:, event_type:)
        timestamp_check = validate_timestamp(headers)
        signature_check = validate_signature(provider, endpoint, headers, payload)

        {
          endpoint_resolved: endpoint.present?,
          signature_verified: signature_check[:verified],
          signature_message: signature_check[:message],
          timestamp_valid: timestamp_check[:valid],
          timestamp_message: timestamp_check[:message],
          event_type: event_type,
          secret_redaction_keys: webhook_configuration.secret_redaction_keys,
          dry_run: true,
          persisted: false
        }.transform_keys(&:to_s)
      end

      def parsed_headers
        value = sandbox_fields.fetch(:headers_json, "").to_s.strip
        return {} if value.empty?

        parsed = JSON.parse(value)
        raise ArgumentError unless parsed.is_a?(Hash)

        parsed.transform_keys { |key| key.to_s.downcase }
      rescue JSON::ParserError
        raise ArgumentError
      end

      def resolved_provider_name
        explicit_provider = sandbox_fields.fetch(:provider_name, "").to_s.strip.downcase
        return explicit_provider if explicit_provider.present?
        return @endpoint.provider_name if @endpoint

        raise ArgumentError
      end

      def resolved_event_type(provider, payload)
        explicit = sandbox_fields.fetch(:event_type, "").to_s.strip
        return explicit if explicit.present?

        extractor = provider.event_type_extractor
        return payload.fetch("type", "") if extractor.nil?

        extracted = invoke_provider_callable(
          extractor,
          payload: payload,
          headers: parsed_headers,
          endpoint: @endpoint,
          controller: self
        )
        extracted.to_s
      end

      def load_endpoint_from_params
        endpoint_id = params[:endpoint_id] || params.dig(:sandbox, :endpoint_id)
        return unless endpoint_id.present?

        @endpoint = endpoint_scope.find_by(id: endpoint_id)
      end

      def load_provider_options
        @providers = webhook_configuration.providers.all.sort_by(&:name)
        @endpoints = endpoint_scope.current.order(:provider_name, :label)
      end

      def validate_signature(provider, endpoint, headers, payload)
        verifier = provider.respond_to?(:signature_verifier_callable) ?
          provider.signature_verifier_callable :
          provider.instance_variable_get(:@signature_verifier)
        return { verified: true, message: "No signature verifier configured." } unless verifier

        result = invoke_provider_callable(
          verifier,
          payload: payload,
          headers: headers,
          endpoint: endpoint,
          controller: self,
          now: Time.current
        )
        { verified: result == true,
          message: (result == true ? "Signature verifier accepted payload." : "Signature verifier rejected payload.") }
      rescue StandardError
        { verified: false, message: "Signature verifier raised an error." }
      end

      def invoke_provider_callable(callable, **kwargs)
        parameters = callable.respond_to?(:parameters) ? callable.parameters : []
        keyword_names = parameters.filter_map { |kind, name| name if %i[key keyreq].include?(kind) }

        if parameters.any? { |kind, _| kind == :keyrest }
          callable.call(**kwargs)
        elsif keyword_names.any?
          callable.call(**kwargs.slice(*keyword_names))
        elsif callable.respond_to?(:arity) && callable.arity.zero?
          callable.call
        else
          callable.call(kwargs[:payload])
        end
      end

      def validate_timestamp(headers)
        raw = headers.fetch("x-webhook-timestamp", "").to_s.strip
        return { valid: true, message: "No timestamp header provided." } if raw.empty?

        parsed = if /\A\d+\z/.match?(raw)
                   Time.at(raw.to_i)
                 else
                   Time.zone.parse(raw)
                 end
        return { valid: false, message: "Timestamp could not be parsed." } if parsed.nil?

        drift = (Time.current - parsed).abs
        if drift <= 5.minutes
          { valid: true, message: "Timestamp drift is within five minutes." }
        else
          { valid: false, message: "Timestamp drift exceeds five minutes." }
        end
      rescue ArgumentError
        { valid: false, message: "Timestamp could not be parsed." }
      end

      def dispatcher_name
        value = webhook_configuration.dispatcher
        value.is_a?(Symbol) ? value.to_s : "custom"
      end
    end
  end
end
