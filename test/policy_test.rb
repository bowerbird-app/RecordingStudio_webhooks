# frozen_string_literal: true

require "test_helper"

class PolicyTest < Minitest::Test
  def test_policy_precedence_is_endpoint_then_action_then_provider_then_default
    default_policy = RecordingStudioWebhooks::Policy.new(
      enabled: true,
      execution_mode: "independent",
      max_retries: 1,
      retry_backoff: 2,
      max_retry_backoff: 10,
      redaction_keys: ["global"],
      deduplicate: true
    )

    resolved = RecordingStudioWebhooks::Policy.resolve(
      default: default_policy,
      provider: { execution_mode: "sequential", max_retries: 2, redaction_keys: ["provider"] },
      action: { max_retries: 3, deduplicate: false, redaction_keys: ["action"] },
      endpoint: { enabled: false, max_retries: 4, redaction_keys: ["endpoint"] },
      required_redaction_keys: ["token"]
    )

    refute resolved.enabled?
    assert_equal "sequential", resolved.execution_mode
    assert_equal 4, resolved.max_retries
    refute resolved.deduplicate?
    assert_equal %w[action endpoint global provider token], resolved.redaction_keys
  end

  def test_invalid_policy_values_fail_closed
    assert_raises(RecordingStudioWebhooks::InvalidPolicyError) do
      RecordingStudioWebhooks::Policy.new(enabled: "yes")
    end
    assert_raises(RecordingStudioWebhooks::InvalidPolicyError) do
      RecordingStudioWebhooks::Policy.new(execution_mode: "parallel")
    end
    assert_raises(RecordingStudioWebhooks::InvalidPolicyError) do
      RecordingStudioWebhooks::Policy.new(max_retries: 21)
    end
  end

  def test_policy_resolver_keeps_endpoint_overrides_above_action_and_provider
    with_fresh_configuration do |configuration|
      provider = configuration.provider "billing", policy: { max_retries: 2, enabled: false }
      action = configuration.action "billing.invoice_paid", ->(_context) {},
        provider: "billing",
        event: "invoice.paid",
        policy: { max_retries: 3, enabled: true }
      endpoint = Struct.new(:policy_overrides, :event_policies).new(
        { max_retries: 4, enabled: false },
        {}
      )

      event_resolution = RecordingStudioWebhooks::PolicyResolver.resolve_event(
        configuration: configuration,
        provider: provider,
        endpoint: endpoint,
        event_type: "invoice.paid"
      )
      action_resolution = RecordingStudioWebhooks::PolicyResolver.resolve_action(
        event_resolution: event_resolution,
        action: action,
        required_redaction_keys: []
      )

      assert_equal 4, action_resolution.policy.max_retries
      refute_predicate action_resolution.policy, :enabled?
    end
  end
end
