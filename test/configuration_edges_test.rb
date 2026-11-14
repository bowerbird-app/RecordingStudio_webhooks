# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class ConfigurationEdgesTest < Minitest::Test
  def test_policy_slots_queue_and_discovery_reject_invalid_values
    with_fresh_configuration do |configuration|
      configuration.framework_policy = { "max_retries" => 2 }
      configuration.global_policy = { "max_retries" => 4 }
      configuration.queue_name = "webhooks.default"
      configuration.dispatcher = :active_job
      configuration.automatic_discovery = false
      configuration.authorization_hook = nil
      configuration.rate_limiter = ->(_context) { true }
      configuration.secret_redaction_keys = %w[api_key token]
      configuration.provenance_keys = ["request_id"]

      assert_equal 2, configuration.framework_policy.max_retries
      assert_equal 4, configuration.global_policy.max_retries
      assert_equal "webhooks.default", configuration.queue_name
      assert_equal "active_job", configuration.report.fetch("dispatcher")
      assert_equal false, configuration.automatic_discovery
      assert_nil configuration.authorization_hook
      assert_equal %w[api_key token], configuration.secret_redaction_keys

      configuration.merge!("queue_name" => "merged_queue", "not_a_setting" => "ignored")
      assert_equal "merged_queue", configuration.queue_name

      configuration.merge!([["content_types", ["application/json"]]])
      assert_equal ["application/json"], configuration.content_types
      assert_equal configuration, configuration.merge!(nil)
    end
  end

  def test_configuration_rejects_invalid_settings
    with_fresh_configuration do |configuration|
      assert_raises(RecordingStudioWebhooks::ConfigurationError) { configuration.queue_name = "bad queue" }
      assert_raises(RecordingStudioWebhooks::ConfigurationError) { configuration.content_types = [] }
      assert_raises(RecordingStudioWebhooks::ConfigurationError) { configuration.secret_redaction_keys = [] }
      assert_raises(RecordingStudioWebhooks::ConfigurationError) { configuration.provenance_keys = ["token"] }
      assert_raises(RecordingStudioWebhooks::ConfigurationError) { configuration.rate_limiter = "limit" }
      assert_raises(RecordingStudioWebhooks::ConfigurationError) { configuration.automatic_discovery = "yes" }
      assert_raises(RecordingStudioWebhooks::ConfigurationError) { configuration.max_payload_bytes = "many" }
    end
  end

  def test_digest_token_uses_a_generated_secret_without_putting_it_in_the_report
    with_fresh_configuration do |configuration|
      secret = SecureRandom.hex(16)
      plain = "rswh_#{SecureRandom.hex(8)}"
      unsigned = configuration.digest_token(plain)

      configuration.token_digest_secret = secret
      signed = configuration.digest_token(plain)

      refute_equal unsigned, signed
      assert_equal 64, signed.bytesize
      refute_includes configuration.report.to_s, secret
      refute_includes configuration.inspect, secret

      configuration.token_digest_secret = nil
      assert_equal unsigned, configuration.digest_token(plain)
      assert_equal false, configuration.token_digest_secret_configured?
    end
  end

  def test_discovery_roots_must_be_existing_directories
    with_fresh_configuration do |configuration|
      Dir.mktmpdir do |directory|
        file = File.join(directory, "notes.txt")
        File.write(file, "not a root")

        assert_raises(RecordingStudioWebhooks::ConfigurationError) { configuration.provider_roots = [file] }
        assert_raises(RecordingStudioWebhooks::ConfigurationError) do
          configuration.action_roots = [File.join(directory, "missing")]
        end

        configuration.provider_roots = [directory]
        assert_equal [File.realpath(directory)], configuration.provider_roots
      end
    end
  end

  def test_provider_and_action_definition_blocks_record_policy
    with_fresh_configuration do |configuration|
      provider = configuration.provider("gamma") do
        policy(max_retries: 2)
        event_policy("invoice.*", max_retries: 1)
      end
      action = configuration.action("gamma.received", provider: "gamma", event: "gamma.received") do
        policy(max_retries: 1)
        handler(->(_context) { true })
        provider("gamma")
        event("gamma.received")
      end

      assert_equal 2, provider.snapshot.dig("policy", "max_retries")
      assert_equal "invoice.*", provider.snapshot.fetch("event_policies").first.fetch("pattern")
      assert_equal "gamma.received", action.name
      assert_equal 1, action.snapshot.dig("policy", "max_retries")
      assert_raises(RecordingStudioWebhooks::ConfigurationError) do
        configuration.action("gamma.bad", priority: "nope", provider: "gamma")
      end
      assert_raises(RecordingStudioWebhooks::ConfigurationError) do
        configuration.action("gamma.missing", provider: "gamma")
      end
    end
  end

  def test_registry_fetch_bang_clear_and_insertion_order
    with_fresh_configuration do |configuration|
      configuration.provider("zeta")
      configuration.provider("alpha")

      names = configuration.providers.map(&:name)

      assert_equal %w[alpha zeta], names
      assert_equal %w[zeta alpha], configuration.providers.insertion_order
      assert_raises(RecordingStudioWebhooks::ConfigurationError) { configuration.providers.fetch!("missing") }

      configuration.providers.clear!
      assert_empty configuration.providers.all
    end
  end
end
