# frozen_string_literal: true

require "test_helper"
require "logger"
require "rack/mock"
require "action_dispatch/http/request"

class SignatureConfigurationTest < Minitest::Test
  Context = Struct.new(:raw_payload, :headers, :endpoint, keyword_init: true)
  SecretHolder = Struct.new(:signing_secret)

  def test_unconfigured_provider_warns_once_and_the_warning_has_no_secret
    with_fresh_configuration do |configuration|
      configuration.token_digest_secret = "digest-key-should-stay-hidden"
      configuration.provider("gap_provider")
      configuration.provider("open_provider", unsigned: true)
      configuration.provider("hmac_provider", hmac: true)

      io = StringIO.new
      Rails.stub(:logger, Logger.new(io)) do
        configuration.warn_unconfigured_providers!
        configuration.warn_unconfigured_providers!
      end

      assert_includes io.string, "gap_provider"
      assert_includes io.string, "not marked unsigned"
      refute_includes io.string, "open_provider"
      refute_includes io.string, "hmac_provider"
      refute_includes io.string, "digest-key-should-stay-hidden"
      assert_equal 1, io.string.scan("gap_provider").size
    end
  end

  def test_configure_warns_when_a_provider_has_no_signature_check
    with_fresh_configuration do
      io = StringIO.new
      Rails.stub(:logger, Logger.new(io)) do
        RecordingStudioWebhooks.configure do |config|
          config.provider("late_gap")
        end
      end

      assert_includes io.string, "late_gap"
      assert_includes io.string, "rejected"
    end
  end

  def test_unsigned_and_hmac_cannot_be_combined
    error = assert_raises(RecordingStudioWebhooks::ConfigurationError) do
      RecordingStudioWebhooks::ProviderDefinition.new("both", unsigned: true, hmac: true)
    end

    assert_includes error.message, "unsigned"
  end

  def test_hmac_options_reject_unknown_keys
    assert_raises(RecordingStudioWebhooks::ConfigurationError) do
      RecordingStudioWebhooks::ProviderDefinition.new("billing", hmac: { algorithm: "sha1" })
    end
  end

  def test_hmac_signature_accepts_a_fresh_body_and_rejects_a_bad_one
    secret = "signing-secret"
    body = "{\"id\":\"evt_1\"}"
    frozen = Time.at(1_700_000_000)
    verifier = RecordingStudioWebhooks::HmacSignature.new

    Time.stub(:now, frozen) do
      timestamp = frozen.to_i.to_s
      signature = OpenSSL::HMAC.hexdigest("SHA256", secret, "#{timestamp}.#{body}")
      assert verifier.call(context(secret, body, timestamp, signature))

      stale = (frozen.to_i - 301).to_s
      stale_signature = OpenSSL::HMAC.hexdigest("SHA256", secret, "#{stale}.#{body}")
      refute verifier.call(context(secret, body, stale, stale_signature))

      future = (frozen.to_i + 301).to_s
      future_signature = OpenSSL::HMAC.hexdigest("SHA256", secret, "#{future}.#{body}")
      refute verifier.call(context(secret, body, future, future_signature))

      edge = (frozen.to_i - verifier_tolerance).to_s
      edge_signature = OpenSSL::HMAC.hexdigest("SHA256", secret, "#{edge}.#{body}")
      assert verifier.call(context(secret, body, edge, edge_signature))

      refute verifier.call(context(secret, body, timestamp, nil))
      refute verifier.call(context(secret, body, nil, signature))
      refute verifier.call(context(secret, body, "not-a-time", signature))
      refute verifier.call(context("", body, timestamp, signature))
    end
  end

  def test_verification_compares_with_secure_compare
    secret = "signing-secret"
    body = "{\"id\":\"evt_1\"}"
    timestamp = "1700000000"
    expected = OpenSSL::HMAC.hexdigest("SHA256", secret, "#{timestamp}.#{body}")
    provided = "ab" * (expected.bytesize / 2)
    seen = nil
    compare = lambda do |left, right|
      seen = [left, right]
      false
    end

    Time.stub(:now, Time.at(timestamp.to_i)) do
      ActiveSupport::SecurityUtils.stub(:secure_compare, compare) do
        refute RecordingStudioWebhooks::HmacSignature.new.call(context(secret, body, timestamp, provided))
      end
    end

    assert_equal [provided, expected], seen
  end

  def test_a_different_length_signature_does_not_call_secure_compare
    secret = "signing-secret"
    body = "{}"
    timestamp = "1700000000"
    Time.stub(:now, Time.at(timestamp.to_i)) do
      ActiveSupport::SecurityUtils.stub(:secure_compare, ->(*) { raise "length leak" }) do
        refute RecordingStudioWebhooks::HmacSignature.new.call(context(secret, body, timestamp, "short"))
      end
    end
  end

  def test_header_names_and_tolerance_are_configurable
    secret = "signing-secret"
    body = "{\"ok\":true}"
    frozen = Time.at(1_700_000_000)
    verifier = RecordingStudioWebhooks::HmacSignature.new(
      signature_header: "X-Provider-Signature",
      timestamp_header: "HTTP_X_PROVIDER_TIMESTAMP",
      tolerance: 60
    )
    timestamp = (frozen.to_i - 50).to_s
    signature = OpenSSL::HMAC.hexdigest("SHA256", secret, "#{timestamp}.#{body}")
    headers = {
      "http_x_provider_signature" => signature,
      "x-provider-timestamp" => timestamp
    }

    Time.stub(:now, frozen) do
      assert verifier.call(Context.new(raw_payload: body, headers: headers, endpoint: SecretHolder.new(secret)))
    end
    refute_includes verifier.inspect, secret
  end

  def test_filtered_path_redacts_the_endpoint_token_segment
    token = "rswh_exampletokenvalue"
    ActionDispatch::Request.prepend(RecordingStudioWebhooks::FilteredInboundPath)
    env = Rack::MockRequest.env_for("http://example.test/webhooks/inbound/#{token}?endpoint_token=#{token}")
    path = ActionDispatch::Request.new(env).filtered_path

    refute_includes path, token
    assert_includes path, "[FILTERED]"
  end

  private

  def context(secret, body, timestamp, signature)
    headers = {}
    headers["x-recording-studio-timestamp"] = timestamp if timestamp
    headers["x-recording-studio-signature"] = signature if signature
    Context.new(raw_payload: body, headers: headers, endpoint: SecretHolder.new(secret))
  end

  def verifier_tolerance
    RecordingStudioWebhooks::HmacSignature::DEFAULT_TOLERANCE
  end
end
