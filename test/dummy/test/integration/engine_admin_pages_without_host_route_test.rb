# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class EngineAdminPagesWithoutHostRouteTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    hide_host_recording_studio_admin_webhooks_path!

    @webhooks_configuration = RecordingStudioWebhooks.configuration
    @original_admin_authorizer = @webhooks_configuration.admin_authorizer
    @original_admin_recording_scope = @webhooks_configuration.admin_recording_scope
    @webhooks_configuration.admin_authorizer = ->(context) { context.actor&.email == "admin@admin.com" }
    @webhooks_configuration.admin_recording_scope = ->(_context) { RecordingStudio::Recording.where(trashed_at: nil) }

    @user = User.find_or_create_by!(email: "admin@admin.com") do |user|
      user.password = "Password123!"
      user.password_confirmation = "Password123!"
    end
    workspace = Workspace.create!(name: "Engine pages #{SecureRandom.hex(4)}")
    @recording = RecordingStudio.root_recording_for(workspace)
    result = RecordingStudioAccessible.bootstrap_owner_access!(
      recording: @recording,
      actor: @user
    )
    raise result.error if result.failure?

    @endpoint = RecordingStudioWebhooks::EndpointLifecycle.create!(
      endpoint: RecordingStudioWebhooks::Endpoint.new(
        recording_studio_recording_id: @recording.id,
        label: "Engine pages endpoint",
        provider_name: "demo",
        identity: { "test" => true },
        metadata: {},
        policy_overrides: {}
      ),
      actor: @user
    )
  end

  teardown do
    @webhooks_configuration.admin_authorizer = @original_admin_authorizer
    @webhooks_configuration.admin_recording_scope = @original_admin_recording_scope
    restore_host_recording_studio_admin_webhooks_path!
  end

  test "engine admin pages render without a host recording_studio_admin_webhooks_path" do
    refute Rails.application.routes.url_helpers.respond_to?(:recording_studio_admin_webhooks_path)

    sign_in @user
    token = @endpoint.issue_token!.plaintext_token
    post "/webhooks/inbound/#{token}",
         params: JSON.generate(id: "evt_engine_pages_1", type: "demo.received"),
         headers: { "CONTENT_TYPE" => "application/json" }
    assert_response :accepted
    event = @endpoint.inbound_events.find_by!(provider_event_id: "evt_engine_pages_1")
    attempt = event.action_attempts.order(:execution_position).first

    [
      "/admin/webhooks",
      "/admin/webhooks/providers",
      "/admin/webhooks/events",
      "/admin/webhooks/endpoints/#{@endpoint.id}/events",
      "/admin/webhooks/attempts/#{attempt.id}",
      "/admin/webhooks/webhook_sandbox",
      "/admin/webhooks/endpoints/#{@endpoint.id}/sandbox"
    ].each do |path|
      get path
      if path == "/admin/webhooks"
        assert_redirected_to "/admin/sections/admin_webhooks"
        follow_redirect!
      end
      assert_response :success, "#{path} should render without recording_studio_admin_webhooks_path"
    end
  end

  private

  def hide_host_recording_studio_admin_webhooks_path!
    helpers = Rails.application.routes.url_helpers
    @hidden_host_admin_webhooks_helpers = {}
    %i[recording_studio_admin_webhooks_path recording_studio_admin_webhooks_url].each do |name|
      next unless helpers.respond_to?(name)

      @hidden_host_admin_webhooks_helpers[name] = helpers.method(name)
      helpers.singleton_class.class_eval do
        undef_method name if method_defined?(name) || private_method_defined?(name)
      end
    end
  end

  def restore_host_recording_studio_admin_webhooks_path!
    helpers = Rails.application.routes.url_helpers
    (@hidden_host_admin_webhooks_helpers || {}).each do |name, original|
      helpers.define_singleton_method(name) do |*args, **kwargs, &block|
        original.call(*args, **kwargs, &block)
      end
    end
  end
end
