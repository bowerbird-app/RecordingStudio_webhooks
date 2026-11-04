# frozen_string_literal: true

require "test_helper"
require "stringio"

class PublicIntakeGuardTest < Minitest::Test
  def setup
    RecordingStudioWebhooks::PublicIntakeGuard.mount_path = "/webhooks"
    RecordingStudioWebhooks::PublicIntakeGuard.reset_discovered_mount_path!
  end

  def teardown
    RecordingStudioWebhooks::PublicIntakeGuard.mount_path = nil
    RecordingStudioWebhooks::PublicIntakeGuard.reset_discovered_mount_path!
  end

  def test_guard_blocks_declared_oversized_intake_before_the_application
    with_fresh_configuration do |configuration|
      configuration.max_payload_bytes = 3
      called = false
      guard = RecordingStudioWebhooks::PublicIntakeGuard.new(->(_environment) { called = true })

      status, _headers, body = guard.call(
        "REQUEST_METHOD" => "POST",
        "PATH_INFO" => "/webhooks/inbound/rswh_123e4567e89b12d3a456426614174000",
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
        "REQUEST_METHOD" => "POST",
        "PATH_INFO" => "/webhooks/inbound/rswh_123e4567e89b12d3a456426614174000",
        "CONTENT_LENGTH" => "3",
        "rack.input" => StringIO.new("{}")
      )

      assert_equal 204, status
      assert_equal({}, observed.fetch("action_dispatch.request.request_parameters"))
      assert_equal({}, observed.fetch("action_dispatch.request.parameters"))
    end
  end

  def test_guard_protects_header_only_inbound_path
    with_fresh_configuration do |configuration|
      configuration.max_payload_bytes = 3
      called = false
      guard = RecordingStudioWebhooks::PublicIntakeGuard.new(->(_environment) { called = true })

      status, _headers, body = guard.call(
        "REQUEST_METHOD" => "POST",
        "PATH_INFO" => "/webhooks/inbound",
        "CONTENT_LENGTH" => "4",
        "rack.input" => StringIO.new("abcd")
      )

      assert_equal 413, status
      assert_equal '{"status":"invalid"}', body.join
      refute called
    end
  end

  def test_guard_does_not_treat_a_provider_only_path_as_public_intake
    called = false
    guard = RecordingStudioWebhooks::PublicIntakeGuard.new(->(_environment) { called = true; [204, {}, []] })

    status, = guard.call(
      "REQUEST_METHOD" => "POST",
      "PATH_INFO" => "/webhooks/inbound/provider-only",
      "CONTENT_LENGTH" => "9999999"
    )

    assert_equal 204, status
    assert called
  end

  def test_guard_leaves_a_non_engine_inbound_request_untouched
    called = false
    guard = RecordingStudioWebhooks::PublicIntakeGuard.new(->(_environment) { called = true; [204, {}, []] })

    status, = guard.call(
      "REQUEST_METHOD" => "POST",
      "PATH_INFO" => "/something/inbound",
      "CONTENT_LENGTH" => "9999999",
      "rack.input" => StringIO.new("abcd")
    )

    assert_equal 204, status
    assert called
  end

  def test_root_engine_mount_guards_inbound
    RecordingStudioWebhooks::PublicIntakeGuard.mount_path = nil
    RecordingStudioWebhooks::PublicIntakeGuard.reset_discovered_mount_path!

    with_engine_mounted_at("/") do
      with_fresh_configuration do |configuration|
        configuration.max_payload_bytes = 3
        called = false
        guard = RecordingStudioWebhooks::PublicIntakeGuard.new(->(_environment) { called = true })

        status, _headers, body = guard.call(
          "REQUEST_METHOD" => "POST",
          "PATH_INFO" => "/inbound",
          "CONTENT_LENGTH" => "4",
          "rack.input" => StringIO.new("abcd")
        )

        assert_equal 413, status
        assert_equal '{"status":"invalid"}', body.join
        refute called
      end
    end
  end

  def test_discover_engine_mount_path_memoizes_after_routes_load
    RecordingStudioWebhooks::PublicIntakeGuard.mount_path = nil
    RecordingStudioWebhooks::PublicIntakeGuard.reset_discovered_mount_path!
    iterations = 0

    with_engine_mounted_at("/admin/webhooks", on_each_route: -> { iterations += 1 }) do
      assert_equal "/admin/webhooks", RecordingStudioWebhooks::PublicIntakeGuard.discover_engine_mount_path
      assert_equal "/admin/webhooks", RecordingStudioWebhooks::PublicIntakeGuard.discover_engine_mount_path
    end

    assert_equal 1, iterations
  end

  private

  def with_engine_mounted_at(path, on_each_route: nil, &block)
    spec = "#{path == '/' ? '/' : path}(.:format)"
    route = Struct.new(:path, :app).new(
      Struct.new(:spec).new(spec),
      RecordingStudioWebhooks::Engine
    )
    routes = Object.new
    routes.define_singleton_method(:each) do |&block|
      on_each_route&.call
      block&.call(route)
      self
    end
    application = Struct.new(:routes).new(Struct.new(:routes).new(routes))
    application.define_singleton_method(:initialized?) { true }

    Rails.stub(:application, application, &block)
  end
end
