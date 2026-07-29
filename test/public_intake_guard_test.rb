# frozen_string_literal: true

require "test_helper"
require "stringio"

class PublicIntakeGuardTest < Minitest::Test
  def test_guard_blocks_declared_oversized_intake_before_the_application
    with_fresh_configuration do |configuration|
      configuration.max_payload_bytes = 3
      called = false
      guard = RecordingStudioWebhooks::PublicIntakeGuard.new(->(_environment) { called = true })

      status, _headers, body = guard.call(
        "PATH_INFO" => "/webhooks/inbound/demo/123e4567-e89b-12d3-a456-426614174000",
        "CONTENT_LENGTH" => "4",
        "rack.input" => StringIO.new("abcd")
      )

      assert_equal 413, status
      assert_equal '{"status":"invalid"}', body.join
      refute called
    end
  end

  def test_guard_prevents_rails_parameter_parsing_for_a_matching_intake_route
    with_fresh_configuration do
      observed = nil
      guard = RecordingStudioWebhooks::PublicIntakeGuard.new(
        ->(environment) { observed = environment; [204, {}, []] }
      )

      status, = guard.call(
        "PATH_INFO" => "/webhooks/inbound/demo/123e4567-e89b-12d3-a456-426614174000",
        "CONTENT_LENGTH" => "3",
        "rack.input" => StringIO.new("{}")
      )

      assert_equal 204, status
      assert_equal({}, observed.fetch("action_dispatch.request.request_parameters"))
      assert_equal({}, observed.fetch("action_dispatch.request.parameters"))
    end
  end

  def test_guard_does_not_treat_a_provider_only_path_as_public_intake
    called = false
    guard = RecordingStudioWebhooks::PublicIntakeGuard.new(->(_environment) { called = true; [204, {}, []] })

    status, = guard.call("PATH_INFO" => "/webhooks/inbound/demo", "CONTENT_LENGTH" => "9999999")

    assert_equal 204, status
    assert called
  end
end
