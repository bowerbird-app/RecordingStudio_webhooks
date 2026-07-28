# frozen_string_literal: true

# app/services/recording_studio_webhooks/action_planner.rb
module RecordingStudioWebhooks
  class ActionPlanner
    def self.call(...) = new(...).call

    def initialize(inbound_event:, endpoint:, endpoint_token:, provider:)
      @inbound_event = inbound_event
      @endpoint = endpoint
      @endpoint_token = endpoint_token
      @provider = provider
    end

    def call
      matching_actions.each_with_index.map do |action, index|
        policy = Policy.resolve(
          default: RecordingStudioWebhooks.configuration.default_policy,
          provider: provider.policy_overrides,
          action: action.policy_overrides,
          endpoint: endpoint.policy_overrides,
          required_redaction_keys: RecordingStudioWebhooks.configuration.secret_redaction_keys
        )

        inbound_event.action_plans.create!(
          action_name: action.name,
          execution_position: index,
          status: policy.enabled? ? "pending" : "skipped",
          completed_at: policy.enabled? ? nil : Time.current,
          endpoint_snapshot: endpoint.snapshot,
          token_snapshot: endpoint_token.snapshot,
          policy_snapshot: policy.to_h,
          action_snapshot: action.snapshot,
          attempt_history: policy.enabled? ? [] : [skipped_history]
        )
      end
    end

    private

    attr_reader :inbound_event, :endpoint, :endpoint_token, :provider

    def matching_actions
      RecordingStudioWebhooks.configuration.actions.matching(provider.name, inbound_event.event_type)
    end

    def skipped_history
      [{ "state" => "skipped", "at" => Time.current.iso8601(6), "attempt" => 0, "error" => "action_disabled" }]
    end
  end
end
