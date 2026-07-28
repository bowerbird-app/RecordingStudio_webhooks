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
        policies = actions.map do |action|
          Policy.resolve(
            default: webhook_configuration.default_policy,
            provider: provider.policy_overrides,
            action: action.policy_overrides,
            endpoint: @endpoint.policy_overrides,
            required_redaction_keys: webhook_configuration.secret_redaction_keys
          )
        end
        redaction_keys = policies.flat_map(&:redaction_keys) + webhook_configuration.secret_redaction_keys

        ImmutableSnapshot.build(
          event_type: event_type,
          payload: Redactor.redact(payload, keys: redaction_keys),
          actions: actions.zip(policies).map do |action, policy|
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
