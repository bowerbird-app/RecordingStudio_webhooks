# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class ConfigurationTest < Minitest::Test
  def test_defaults_are_inbound_safe_and_report_has_no_digest_secret
    with_fresh_configuration do |configuration|
      assert_equal :sidekiq, configuration.dispatcher
      assert_equal 1_048_576, configuration.max_payload_bytes
      assert_equal 18, configuration.endpoint_token_bytesize
      assert_equal true, configuration.default_policy.deduplicate?
      assert_nil configuration.admin_authorizer

      configuration.token_digest_secret = "not-for-reporting"
      report = configuration.report

      refute_includes report.to_s, "not-for-reporting"
      assert_equal false, report.fetch("admin_authorizer_configured")
      assert_equal "sidekiq", report.fetch("dispatcher")
    end
  end

  def test_configuration_accepts_explicit_admin_and_dispatcher_overrides
    with_fresh_configuration do |configuration|
      authorizer = ->(_context) { true }
      dispatcher = ->(_plan_id, _wait_until = nil) { true }

      configuration.admin_authorizer = authorizer
      configuration.admin_recording_scope = ->(_context) { [] }
      configuration.dispatcher = dispatcher
      configuration.max_payload_bytes = "2048"
      configuration.endpoint_token_bytesize = "16"
      configuration.content_types = ["application/json", "application/problem+json"]

      assert_same authorizer, configuration.admin_authorizer
      assert_same dispatcher, configuration.dispatcher
      assert_equal 2048, configuration.max_payload_bytes
      assert_equal 16, configuration.endpoint_token_bytesize
      assert_equal ["application/json", "application/problem+json"], configuration.content_types
      assert_equal "custom", configuration.report.fetch("dispatcher")
    end
  end

  def test_discovery_requires_explicit_roots_and_registers_in_lexical_order
    with_fresh_configuration do |configuration|
      Dir.mktmpdir do |directory|
        File.write(
          File.join(directory, "z_provider.rb"),
          'RecordingStudioWebhooks.register_provider("zebra")'
        )
        File.write(
          File.join(directory, "a_provider.rb"),
          'RecordingStudioWebhooks.register_provider("alpha")'
        )

        configuration.provider_roots = [directory]
        configuration.automatic_discovery = true
        discovered = configuration.discover!

        assert_equal discovered.sort, discovered
        assert_equal %w[alpha zebra], configuration.providers.all.map(&:name)
      end
    end
  end

  def test_invalid_configuration_is_rejected
    with_fresh_configuration do |configuration|
      assert_raises(RecordingStudioWebhooks::ConfigurationError) { configuration.max_payload_bytes = 0 }
      assert_raises(RecordingStudioWebhooks::ConfigurationError) { configuration.endpoint_token_bytesize = 11 }
      assert_raises(RecordingStudioWebhooks::ConfigurationError) { configuration.dispatcher = Object.new }
      assert_raises(RecordingStudioWebhooks::ConfigurationError) { configuration.admin_authorizer = "yes" }
    end
  end
end
