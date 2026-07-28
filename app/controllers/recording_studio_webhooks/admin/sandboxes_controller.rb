# frozen_string_literal: true

module RecordingStudioWebhooks
  module Admin
    class SandboxesController < BaseController
      before_action :load_endpoint

      def show
      end

      def create
        raw_payload = sandbox_fields.fetch(:payload, "").to_s
        raise ArgumentError if raw_payload.bytesize > webhook_configuration.max_payload_bytes

        payload = JSON.parse(raw_payload)
        event_type = sandbox_fields.fetch(:event_type, "").to_s
        EventPattern.validate_event_name!(event_type)

        provider = webhook_configuration.providers.fetch(@endpoint.provider_name)
        raise ArgumentError unless provider

        @sandbox_result = build_sandbox_result(provider, payload, event_type)
        render :show
      rescue ArgumentError, JSON::ParserError, InvalidEventPatternError
        @form_error = "Provide a JSON payload and a valid event type."
        render :show, status: :unprocessable_entity
      end

      private

      def sandbox_fields
        params.require(:sandbox).permit(:event_type, :payload)
      end

      def build_sandbox_result(provider, payload, event_type)
        actions = webhook_configuration.actions.matching(provider.name, event_type)
        event_resolution = PolicyResolver.resolve_event(
          configuration: webhook_configuration,
          provider: provider,
          endpoint: @endpoint,
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
              max_retries: policy.max_retries
            }
          end
        )
      end
    end
  end
end
