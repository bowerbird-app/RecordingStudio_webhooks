# frozen_string_literal: true

require "test_helper"
require "recording_studio_accessible"

class AdminAccessibleAuthorizationTest < Minitest::Test
  Context = Struct.new(:actor, :controller, :permission, :recording, keyword_init: true)
  Controller = Struct.new(:root) do
    def current_root_recording
      root
    end
  end
  PrivateRootController = Class.new do
    def initialize(root)
      @root = root
    end

    private

    def current_root_recording
      @root
    end
  end

  def test_defaults_go_through_accessible
    with_fresh_configuration do |configuration|
      assert_same(
        RecordingStudioWebhooks::Configuration::DEFAULT_ADMIN_AUTHORIZER,
        configuration.admin_authorizer
      )
      assert_same(
        RecordingStudioWebhooks::Configuration::DEFAULT_ADMIN_RECORDING_SCOPE,
        configuration.admin_recording_scope
      )
    end
  end

  def test_hosts_can_clear_the_authorizer_to_deny_everyone
    with_fresh_configuration do |configuration|
      configuration.admin_authorizer = nil
      configuration.admin_recording_scope = nil

      assert_nil configuration.admin_authorizer
      assert_nil configuration.admin_recording_scope
      assert_equal false, configuration.report.fetch("admin_authorizer_configured")
      assert_equal false, configuration.report.fetch("admin_recording_scope_configured")
    end
  end

  def test_authorizer_denies_without_an_actor_or_current_root
    actor = Object.new
    recording = Object.new

    refute RecordingStudioWebhooks::Admin::AccessibleAuthorization.authorized?(
      Context.new(actor: nil, controller: Controller.new(recording), permission: :view)
    )
    refute RecordingStudioWebhooks::Admin::AccessibleAuthorization.authorized?(
      Context.new(actor: actor, controller: Controller.new(nil), permission: :view)
    )
  end

  def test_authorizer_asks_accessible_for_view_and_admin
    actor = Object.new
    recording = Object.new
    seen = []

    check = lambda do |actor:, recording:, role:|
      seen << [actor, recording, role]
      role == :admin
    end

    RecordingStudioAccessible.stub(:authorized?, check) do
      refute RecordingStudioWebhooks::Admin::AccessibleAuthorization.authorized?(
        Context.new(actor: actor, controller: Controller.new(recording), permission: :view)
      )
      assert RecordingStudioWebhooks::Admin::AccessibleAuthorization.authorized?(
        Context.new(actor: actor, controller: Controller.new(recording), permission: :admin)
      )
    end

    assert_equal [[actor, recording, :view], [actor, recording, :admin]], seen
  end

  def test_authorizer_fails_closed_when_accessible_raises
    actor = Object.new
    recording = Object.new

    RecordingStudioAccessible.stub(:authorized?, ->(**) { raise "policy exploded" }) do
      refute RecordingStudioWebhooks::Admin::AccessibleAuthorization.authorized?(
        Context.new(actor: actor, controller: Controller.new(recording), permission: :view)
      )
    end
  end

  def test_authorizer_ignores_a_private_current_root_recording
    actor = Object.new
    recording = Object.new

    RecordingStudioAccessible.stub(:authorized?, true) do
      refute RecordingStudioWebhooks::Admin::AccessibleAuthorization.authorized?(
        Context.new(actor: actor, controller: PrivateRootController.new(recording), permission: :view)
      )
    end
  end

  def test_authorizer_uses_a_recording_threaded_on_context
    actor = Object.new
    recording = Object.new
    seen = []

    check = lambda do |actor:, recording:, role:|
      seen << [actor, recording, role]
      true
    end

    RecordingStudioAccessible.stub(:authorized?, check) do
      assert RecordingStudioWebhooks::Admin::AccessibleAuthorization.authorized?(
        Context.new(
          actor: actor,
          controller: PrivateRootController.new(Object.new),
          permission: :view,
          recording: recording
        )
      )
    end

    assert_equal [[actor, recording, :view]], seen
  end

  def test_recording_scope_is_empty_when_accessible_denies
    actor = Object.new
    recording = Object.new

    RecordingStudioAccessible.stub(:authorized?, ->(**) { false }) do
      scope = RecordingStudioWebhooks::Admin::AccessibleAuthorization.recordings_for(
        Context.new(actor: actor, controller: Controller.new(recording), permission: :view)
      )
      assert_empty Array(scope.respond_to?(:to_a) ? scope.to_a : scope)
    end
  end
end
