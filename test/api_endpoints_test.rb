# frozen_string_literal: true

require "test_helper"

class ApiEndpointsTest < Minitest::Test
  def test_named_endpoints_register_through_recording_studio_api
    source = [
      File.read(File.expand_path("../lib/recording_studio_webhooks/api/endpoints.rb", __dir__)),
      File.read(File.expand_path("../lib/recording_studio_webhooks/api/endpoint_handlers.rb", __dir__)),
      File.read(File.expand_path("../lib/recording_studio_webhooks/api/endpoint_registrations.rb", __dir__))
    ].join("\n")
    engine = File.read(File.expand_path("../lib/recording_studio_webhooks/engine.rb", __dir__))
    gemspec = File.read(File.expand_path("../recording_studio_webhooks.gemspec", __dir__))
    access = File.read(File.expand_path("../lib/recording_studio_webhooks/api/access.rb", __dir__))

    assert_includes source, "RecordingStudioApi.register_endpoint"
    assert_includes source, "return unless defined?(::RecordingStudioApi)"
    assert_equal 1, source.scan("defined?").size
    refute_includes source, "respond_to?"
    refute_includes source, "const_set"
    refute_includes source, "remove_const"
    refute_includes source, "api_authorize"
    refute_includes source, "register_recordable_type_api"
    assert_includes source, "access_grant.authorize!"
    assert_includes source, "role: ROLE"
    assert_includes source, "ROLE = :admin"
    assert_includes source, "EndpointLifecycle.create!"
    assert_includes source, "EndpointLifecycle.update!"
    assert_includes source, "issue_token!"
    assert_includes source, "revoke!"
    assert_includes source, "plaintext_token"
    assert_includes source, "Admin::AccessibleAuthorization.descendant_scope"
    assert_includes source, 'title: "Webhook Endpoint - Create"'
    assert_includes source, 'summary: "Webhook Endpoint - Create"'
    assert_includes source, 'title: "Webhook Token - Revoke"'
    assert_includes source, 'summary: "Webhook Token - Revoke"'
    refute_includes source, "InboundIntake"
    refute_includes source, "RecoverActionAttempts"
    refute_includes source, "register_provider"
    refute_includes source, "register_action"

    assert_includes engine, 'initializer "recording_studio_webhooks.api_endpoints"'
    assert_includes engine, "RecordingStudioWebhooks::Api::Endpoints.register!"

    refute_includes gemspec, "recording_studio_api"
    refute_includes access, "register_endpoint"
  end
end
