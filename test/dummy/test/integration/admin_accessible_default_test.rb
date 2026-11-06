# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class AdminAccessibleDefaultTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @configuration = RecordingStudioWebhooks.configuration
    assert_same(
      RecordingStudioWebhooks::Configuration::DEFAULT_ADMIN_AUTHORIZER,
      @configuration.admin_authorizer
    )
    assert_same(
      RecordingStudioWebhooks::Configuration::DEFAULT_ADMIN_RECORDING_SCOPE,
      @configuration.admin_recording_scope
    )
  end

  teardown do
    Current.actor = nil
  end

  test "Accessible owners can open webhook administration on the current root" do
    user = create_user!("owner-#{SecureRandom.hex(4)}@admin.com")
    recording = grant_current_root!(user, role: :admin)
    create_endpoint!(recording, user)
    Current.actor = user

    sign_in user
    get "/admin/webhooks/providers"

    assert_response :success
    assert_select "h1", text: "Providers"
  end

  test "signed-in people without Accessible access cannot open webhook administration" do
    user = create_user!("viewer-#{SecureRandom.hex(4)}@example.com")
    Workspace.create!(name: "Locked #{SecureRandom.hex(4)}")

    sign_in user
    get "/admin/webhooks/providers"

    assert_response :not_found
  end

  test "view access can read webhook administration and cannot create endpoints" do
    user = create_user!("reader-#{SecureRandom.hex(4)}@admin.com")
    grant_current_root!(user, role: :view)

    sign_in user
    get "/admin/webhooks/providers"
    assert_response :success

    post "/admin/webhooks/endpoints", params: {
      endpoint: { label: "Should not create", provider_name: "demo", enabled: true }
    }
    assert_response :not_found
    assert_equal 0, RecordingStudioWebhooks::Endpoint.where(label: "Should not create").count
  end

  test "a missing recording scope does not list every recording" do
    user = create_user!("scoped-#{SecureRandom.hex(4)}@admin.com")
    recording = grant_current_root!(user, role: :admin)
    endpoint = create_endpoint!(recording, user)
    original_scope = @configuration.admin_recording_scope
    original_authorizer = @configuration.admin_authorizer
    @configuration.admin_authorizer = ->(context) { context.actor == user }
    @configuration.admin_recording_scope = nil

    sign_in user
    get "/admin/webhooks/endpoints/#{endpoint.id}/events"

    assert_response :not_found
  ensure
    @configuration.admin_recording_scope = original_scope
    @configuration.admin_authorizer = original_authorizer
  end

  private

  def create_user!(email)
    User.find_or_create_by!(email: email) do |user|
      user.password = "Password123!"
      user.password_confirmation = "Password123!"
    end
  end

  def grant_current_root!(actor, role:)
    workspace = Workspace.find_or_create_by!(name: "Studio Workspace")
    recording = RecordingStudio.root_recording_for(workspace)
    owner = create_user!("studio-owner@admin.com")

    unless RecordingStudioAccessible.authorized?(actor: owner, recording: recording, role: :admin)
      result = RecordingStudioAccessible.bootstrap_owner_access!(recording: recording, actor: owner)
      if result.failure?
        result = RecordingStudioAccessible.grant_access(
          recording: recording,
          actor: owner,
          role: :admin,
          manager_actor: owner
        )
      end
      raise result.error if result.failure?
    end

    unless actor == owner && role == :admin
      result = RecordingStudioAccessible.grant_access(
        recording: recording,
        actor: actor,
        role: role,
        manager_actor: owner
      )
      raise result.error if result.failure?
    end

    recording
  end

  def create_endpoint!(recording, actor)
    RecordingStudioWebhooks::EndpointLifecycle.create!(
      endpoint: RecordingStudioWebhooks::Endpoint.new(
        recording_studio_recording_id: recording.id,
        label: "Accessible default #{SecureRandom.hex(4)}",
        provider_name: "demo",
        identity: { "test" => true },
        metadata: {},
        policy_overrides: {}
      ),
      actor: actor
    )
  end
end
