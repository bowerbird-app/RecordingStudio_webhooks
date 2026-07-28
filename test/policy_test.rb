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
end
