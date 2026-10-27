# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class AdminLayoutTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @configuration = RecordingStudioWebhooks.configuration
    @original_layout = @configuration.layout
    @original_authorizer = @configuration.admin_authorizer
    @original_scope = @configuration.admin_recording_scope
    @configuration.layout = nil
    @configuration.admin_authorizer = ->(context) { context.actor&.email == "admin@admin.com" }
    @configuration.admin_recording_scope = ->(_context) { RecordingStudio::Recording.where(trashed_at: nil) }

    @user = User.find_or_create_by!(email: "admin@admin.com") do |user|
      user.password = "Password123!"
      user.password_confirmation = "Password123!"
    end
    workspace = Workspace.create!(name: "Layout #{SecureRandom.hex(4)}")
    recording = RecordingStudio.root_recording_for(workspace)
    result = RecordingStudioAccessible.bootstrap_owner_access!(recording: recording, actor: @user)
    raise result.error if result.failure?

    sign_in @user
  end

  teardown do
    @configuration.layout = @original_layout
    @configuration.admin_authorizer = @original_authorizer
    @configuration.admin_recording_scope = @original_scope
  end

  test "admin pages inherit the engine layout and render one heading" do
    engine = RecordingStudioWebhooks::ApplicationController
    admin = RecordingStudioWebhooks::Admin::BaseController
    assert_same engine.send(:recording_studio_layout_block), admin.send(:recording_studio_layout_block)
    assert_empty RecordingStudio::Layout.hardcoded_layout_paths(Rails.root)
    assert_empty RecordingStudio::Layout.hardcoded_layout_paths(RecordingStudioWebhooks::Engine.root)

    get "/admin/webhooks/providers"

    assert_response :success
    assert_equal "noindex, nofollow", response.headers["X-Robots-Tag"]
    assert_select "body[data-recording-studio-default-layout]"
    assert_select "h1", count: 1, text: "Providers"
    assert_match(/Close/, response.body)
    assert_operator stylesheet_index("flat_pack/variables"), :<, stylesheet_index("tailwind")
    assert_operator stylesheet_index("flat_pack/application"), :<, stylesheet_index("tailwind")
    assert_operator stylesheet_index("flat_pack/rich_text"), :<, stylesheet_index("tailwind")
  end

  test "a false layout and a named layout replace the shared default" do
    get "/admin/webhooks/endpoints/new"
    assert_response :success
    assert_select "h1", count: 1, text: "New webhook endpoint"

    @configuration.layout = "recording_studio_webhooks/application"
    get "/admin/webhooks/providers"
    assert_response :success
    assert_select "body[data-recording-studio-default-layout]", count: 0
    assert_select "h1", count: 1, text: "Providers"
    assert_operator stylesheet_index("flat_pack/variables"), :<, stylesheet_index("flat_pack/application")

    @configuration.layout = ->(controller:) { controller.action_name == "index" ? false : nil }
    get "/admin/webhooks/providers"
    assert_response :success
    refute_includes response.body, "data-recording-studio-default-layout"
    assert_select "h1", count: 0
  end

  private

  def stylesheet_index(name)
    index = response.body.index(%(#{name}))
    assert index, "expected stylesheet #{name}"
    index
  end
end
