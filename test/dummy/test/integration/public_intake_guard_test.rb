# frozen_string_literal: true

require "test_helper"

class PublicIntakeGuardIntegrationTest < ActionDispatch::IntegrationTest
  setup do
    RecordingStudioWebhooks::PublicIntakeGuard.reset_discovered_mount_path!
    RecordingStudioWebhooks::PublicIntakeGuard.mount_path = nil
  end

  teardown do
    RecordingStudioWebhooks::PublicIntakeGuard.mount_path = nil
    RecordingStudioWebhooks::PublicIntakeGuard.reset_discovered_mount_path!
  end

  test "discover_engine_mount_path finds the dummy app engine mount" do
    assert_equal "/admin/webhooks", RecordingStudioWebhooks::PublicIntakeGuard.discover_engine_mount_path
  end

  test "engine-mounted inbound with oversized Content-Length is stopped by the guard" do
    original_limit = RecordingStudioWebhooks.configuration.max_payload_bytes
    RecordingStudioWebhooks.configuration.max_payload_bytes = 8

    env = Rack::MockRequest.env_for(
      "/admin/webhooks/inbound",
      method: "POST",
      input: "{}",
      "CONTENT_TYPE" => "application/json"
    )
    env["CONTENT_LENGTH"] = "9"

    status, headers, response_body = Rails.application.call(env)
    body = +""
    response_body.each { |chunk| body << chunk }
    response_body.close if response_body.respond_to?(:close)

    assert_equal 413, status
    assert_equal RecordingStudioWebhooks::PublicIntakeGuard::INVALID_BODY, body
    assert_equal(
      RecordingStudioWebhooks::PublicIntakeGuard::INVALID_BODY.bytesize.to_s,
      headers["content-length"] || headers["Content-Length"]
    )
  ensure
    RecordingStudioWebhooks.configuration.max_payload_bytes = original_limit
  end

  test "engine-mounted JSON inbound is guarded instead of parsed by Rails" do
    env = Rack::MockRequest.env_for(
      "/admin/webhooks/inbound",
      method: "POST",
      input: "this is not json {",
      "CONTENT_TYPE" => "application/json"
    )

    status, _headers, response_body = Rails.application.call(env)
    body = +""
    response_body.each { |chunk| body << chunk }
    response_body.close if response_body.respond_to?(:close)

    assert_equal 401, status
    assert_equal({ "status" => "unauthorized" }, JSON.parse(body))
  end
end
