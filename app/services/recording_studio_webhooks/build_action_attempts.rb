# frozen_string_literal: true

module RecordingStudioWebhooks
  class BuildActionAttempts
    def self.call(...) = new(...).call

    def initialize(inbound_event:, provider:, resolution:)
      @inbound_event = inbound_event
      @provider = provider
      @resolution = resolution
    end

    def call
      matching_actions.each_with_index.map do |action, position|
        action_resolution = PolicyResolver.resolve_action(
          event_resolution: resolution,
          action: action,
          required_redaction_keys: RecordingStudioWebhooks.configuration.secret_redaction_keys
        )
        inbound_event.action_attempts.create!(
          action_name: action.name,
          execution_position: position,
          status: action_resolution.enabled? ? "pending" : "skipped",
          attempts: 0,
          completed_at: action_resolution.enabled? ? nil : Time.current,
          last_error: action_resolution.enabled? ? nil : "action_disabled",
          endpoint_snapshot: inbound_event.endpoint_snapshot,
          token_snapshot: inbound_event.token_snapshot,
          policy_snapshot: action_resolution.to_h,
          action_snapshot: action.snapshot,
          attempt_history: if action_resolution.enabled?
                             []
                           else
                             [{
                               "status" => "skipped",
                               "at" => Time.current.iso8601,
                               "attempt" => 0,
                               "error" => "action_disabled"
                             }]
                           end
        )
      end
    end

    private

    attr_reader :inbound_event, :provider, :resolution

    def matching_actions
      RecordingStudioWebhooks.configuration.actions.matching(provider.name, inbound_event.event_type)
    end
  end
end
