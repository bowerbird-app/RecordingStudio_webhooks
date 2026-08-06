# frozen_string_literal: true

require "test_helper"

class SecurityPrimitivesTest < Minitest::Test
  def test_redactor_filters_nested_secret_keys_without_mutating_input
    payload = {
      "customer" => {
        "token" => "super-secret",
        "name" => "Ada"
      },
      "items" => [{ "api_key" => "also-secret", "sku" => "sku_1" }]
    }

    redacted = RecordingStudioWebhooks::Redactor.redact(payload, keys: ["custom_secret"])

    assert_equal "[FILTERED]", redacted.dig("customer", "token")
    assert_equal "[FILTERED]", redacted.dig("items", 0, "api_key")
    assert_equal "Ada", redacted.dig("customer", "name")
    assert_equal "super-secret", payload.dig("customer", "token")
  end

  def test_canonical_json_has_a_stable_digest_for_equivalent_objects
    first = { "b" => [2, { "a" => true }], "a" => 1 }
    second = { a: 1, b: [2, { a: true }] }

    assert_equal(
      RecordingStudioWebhooks::CanonicalJson.digest(first),
      RecordingStudioWebhooks::CanonicalJson.digest(second)
    )
  end

  def test_token_digest_is_constant_time_comparable_and_secret_is_not_inspectable
    with_fresh_configuration do |configuration|
      configuration.token_digest_secret = "credential-store-value"
      digest = RecordingStudioWebhooks::TokenDigest.digest("rswh_example")

      assert RecordingStudioWebhooks::TokenDigest.secure_compare(digest, digest.dup)
      refute RecordingStudioWebhooks::TokenDigest.secure_compare(digest, "different")
      refute_includes configuration.inspect, "credential-store-value"
    end
  end

  def test_immutable_snapshot_freezes_nested_values
    snapshot = RecordingStudioWebhooks::ImmutableSnapshot.build(
      endpoint: { identity: ["stable"] }
    )

    assert_predicate snapshot, :frozen?
    assert_predicate snapshot.fetch("endpoint"), :frozen?
    assert_predicate snapshot.dig("endpoint", "identity"), :frozen?
    assert_raises(FrozenError) { snapshot.fetch("endpoint")["new"] = "value" }
  end
end
