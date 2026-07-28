# frozen_string_literal: true

# app/services/recording_studio_webhooks/action_planner.rb
module RecordingStudioWebhooks
  # Materializes deterministic action work as operational attempt rows. The
  # incoming log's execution mode is copied to every row and never re-resolved.
  class ActionPlanner
    def self.call(...) = new(...).call

    def initialize(incoming_webhook_log:, provider:, resolution:)
      @incoming_webhook_log = incoming_webhook_log
      @provider = provider
      @resolution = resolution
    end

    def call
      matching_actions.each_with_index.map do |action, sequence|
        action_resolution = PolicyResolver.resolve_action(
          event_resolution: resolution,
          action: action,
          required_redaction_keys: RecordingStudioWebhooks.configuration.secret_redaction_keys
        )
        incoming_webhook_log.webhook_action_attempts.create!(
          action_key: action.name,
          sequence: sequence,
          attempt_number: 1,
          status: action_resolution.enabled? ? "pending" : "skipped",
          matching_provenance: matching_provenance(action),
          matching_fingerprint: matching_fingerprint(action),
          action_source: action.source,
          action_fingerprint: action.fingerprint,
          policy_source: resolution.source,
          policy_pattern: resolution.pattern,
          execution_mode: resolution.execution_mode,
          policy_fingerprint: resolution.fingerprint,
          max_retries: action_resolution.policy.max_retries,
          retry_backoff: action_resolution.policy.retry_backoff,
          max_retry_backoff: action_resolution.policy.max_retry_backoff,
          completed_at: action_resolution.enabled? ? nil : Time.current,
          last_error: action_resolution.enabled? ? nil : "action_disabled"
        )
      end
    end

    private

    attr_reader :incoming_webhook_log, :provider, :resolution

    def matching_actions
      RecordingStudioWebhooks.configuration.actions.matching(provider.name, incoming_webhook_log.event_type)
    end

    def matching_provenance(action)
      {
        provider_name: provider.name,
        provider_definition_fingerprint: provider.fingerprint,
        event_type: incoming_webhook_log.event_type,
        event_pattern: action.event_pattern.value,
        priority: action.priority,
        sequence_order: "priority,specificity,key"
      }
    end

    def matching_fingerprint(action)
      CanonicalJson.digest(
        provider_fingerprint: provider.fingerprint,
        provider_name: provider.name,
        event_type: incoming_webhook_log.event_type,
        action_key: action.name,
        action_fingerprint: action.fingerprint,
        event_pattern: action.event_pattern.value,
        priority: action.priority
      )
    end
  end
end
