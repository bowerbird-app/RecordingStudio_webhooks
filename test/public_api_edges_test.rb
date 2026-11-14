# frozen_string_literal: true

require "test_helper"

class PublicApiEdgesTest < Minitest::Test
  def test_redactor_filters_numbers_secret_locations_and_non_json_values
    redacted = RecordingStudioWebhooks::Redactor.redact(
      {
        "count" => 2,
        "enabled" => true,
        "note" => nil,
        "location" => "vault://tenant/signing-key",
        "when" => Object.new
      },
      keys: []
    )

    assert_equal 2, redacted.fetch("count")
    assert_equal true, redacted.fetch("enabled")
    assert_nil redacted.fetch("note")
    assert_equal "[FILTERED]", redacted.fetch("location")
    assert_equal "[FILTERED]", redacted.fetch("when")
  end

  def test_canonical_json_rejects_values_that_are_not_json
    assert_raises(ArgumentError) do
      RecordingStudioWebhooks::CanonicalJson.digest({ "when" => Time.utc(2026, 1, 1) })
    end
  end

  def test_immutable_snapshot_stringifies_unknown_values_and_symbols
    label = Object.new
    def label.to_s = "billing"

    snapshot = RecordingStudioWebhooks::ImmutableSnapshot.build({ label: :billing, item: label })

    assert_equal "billing", snapshot.fetch("label")
    assert_equal "billing", snapshot.fetch("item")
    assert snapshot.frozen?
  end

  def test_result_reports_success_and_omits_the_record_from_its_hash
    result = RecordingStudioWebhooks::Result.new(
      status: 202, code: :accepted, record: Object.new, details: { count: 1 }
    )
    failure = RecordingStudioWebhooks::Result.new(status: 503, code: "unavailable")

    assert_equal true, result.success?
    assert_equal false, result.failure?
    assert_equal true, failure.failure?
    assert_equal 202, result.to_h.fetch("status")
    assert_equal "accepted", result.to_h.fetch("code")
    assert_equal 1, result.to_h.dig("details", "count")
    refute result.to_h.key?("record")
  end

  def test_policy_valid_override_rejects_unknown_options_and_new_requires_an_integer
    assert_equal false, RecordingStudioWebhooks::Policy.valid_override?(mystery: 1)
    assert_equal true, RecordingStudioWebhooks::Policy.valid_override?(max_retries: 1)

    error = assert_raises(RecordingStudioWebhooks::InvalidPolicyError) do
      RecordingStudioWebhooks::Policy.new("max_retries" => "nope")
    end
    assert_includes error.message, "integer"
  end

  def test_gateway_rejects_an_unusable_root_and_scrubs_metadata
    gateway = RecordingStudioWebhooks::RecordingStudioGateway

    unavailable = assert_raises(RecordingStudioWebhooks::RecordingStudioUnavailableError) do
      gateway.root_recording!(Object.new)
    end
    assert_equal "Recording Studio is unavailable", unavailable.message

    gateway.stub(:available?, true) do
      error = assert_raises(RecordingStudioWebhooks::RecordingStudioConfigurationError) do
        RecordingStudio.stub(:root_recording?, ->(*) { raise StandardError, "boom" }) do
          gateway.root_recording!(Object.new)
        end
      end
      assert_equal "recording is not a usable root", error.message

      selected = assert_raises(RecordingStudioWebhooks::RecordingStudioConfigurationError) do
        RecordingStudio.stub(:root_recording?, lambda { |*|
          raise RecordingStudioWebhooks::RecordingStudioConfigurationError, "recording must be a selected root"
        }) do
          gateway.root_recording!(Object.new)
        end
      end
      assert_equal "recording must be a selected root", selected.message
    end

    scrubbed = RecordingStudioWebhooks::RecordingStudioGateway.safe_metadata(
      "count" => 2,
      "tags" => ["billing"],
      "location" => "vault://tenant/key",
      "when" => Object.new
    )

    assert_equal 2, scrubbed.fetch("count")
    assert_equal ["billing"], scrubbed.fetch("tags")
    assert_equal "[FILTERED]", scrubbed.fetch("location")
    assert_includes scrubbed.fetch("when"), "Object"
  end
end
