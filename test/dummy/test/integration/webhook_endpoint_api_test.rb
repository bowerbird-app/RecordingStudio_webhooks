# frozen_string_literal: true

require "test_helper"

class WebhookEndpointApiTest < ActionDispatch::IntegrationTest
  setup do
    @admin = create_user!("api-admin-#{SecureRandom.hex(4)}@example.com")
    @viewer = create_user!("api-viewer-#{SecureRandom.hex(4)}@example.com")
    Current.actor = @admin
    @workspace = Workspace.create!(name: "API Root #{SecureRandom.hex(4)}")
    @root = RecordingStudio.root_recording_for(@workspace)
    @admin_access = bootstrap_owner!(@root, @admin)
    @viewer_access = grant_access!(@root, @viewer, :view, manager: @admin)
    @other_workspace = Workspace.create!(name: "Other Root #{SecureRandom.hex(4)}")
    @other_root = RecordingStudio.root_recording_for(@other_workspace)
    @other_access = bootstrap_owner!(@other_root, @admin)
    @admin_token = issue_access_token(@admin_access, "Admin webhook API")
    @view_token = issue_access_token(@viewer_access, "View webhook API", manager: @admin)
    @other_token = issue_access_token(@other_access, "Other root webhook API")
    Current.actor = nil
  end

  teardown do
    Current.actor = nil
  end

  test "admin token lists creates shows and updates endpoints on its own root" do
    get "/recording_studio_api/api/v1/webhook-endpoints", headers: bearer(@admin_token)
    assert_response :success
    assert_equal [], JSON.parse(response.body).fetch("records")

    post "/recording_studio_api/api/v1/webhook-endpoints",
         params: { label: "Billing hook", provider_name: "billing", enabled: true },
         as: :json,
         headers: bearer(@admin_token)
    assert_response :success
    created = JSON.parse(response.body)
    refute created.key?("token")
    assert_equal "Billing hook", created.fetch("label")
    assert_equal "billing", created.fetch("provider_name")
    created_recording = RecordingStudio::Recording.find(created.fetch("recording_studio_recording_id"))
    assert_equal @root.id, created_recording.root_recording_id

    get "/recording_studio_api/api/v1/webhook-endpoints/#{created.fetch('id')}",
        headers: bearer(@admin_token)
    assert_response :success
    shown = JSON.parse(response.body)
    refute shown.key?("token")
    assert_equal "Billing hook", shown.fetch("label")

    patch "/recording_studio_api/api/v1/webhook-endpoints/#{created.fetch('id')}",
          params: { label: "Billing hook west", enabled: false },
          as: :json,
          headers: bearer(@admin_token)
    assert_response :success
    updated = JSON.parse(response.body)
    assert_equal "Billing hook west", updated.fetch("label")
    assert_equal false, updated.fetch("enabled")
    refute updated.key?("token")
  end

  test "issue returns the plaintext token once and revoke hides it from later reads" do
    endpoint = create_endpoint!(@root, @admin, "Token hook")

    post "/recording_studio_api/api/v1/webhook-endpoints/#{endpoint.id}/tokens",
         as: :json,
         headers: bearer(@admin_token)
    assert_response :success
    issued = JSON.parse(response.body)
    plaintext = issued.fetch("token")
    assert_match(/\Arswh_/, plaintext)
    assert_equal issued.fetch("prefix"), plaintext.first(13)

    get "/recording_studio_api/api/v1/webhook-endpoints/#{endpoint.id}",
        headers: bearer(@admin_token)
    assert_response :success
    body = response.body
    refute_includes body, plaintext
    refute JSON.parse(body).key?("token")

    get "/recording_studio_api/api/v1/webhook-endpoints", headers: bearer(@admin_token)
    assert_response :success
    index_body = response.body
    refute_includes index_body, plaintext
    JSON.parse(index_body).fetch("records").each { |record| refute record.key?("token") }

    post "/recording_studio_api/api/v1/webhook-tokens/#{issued.fetch('id')}/revoke",
         as: :json,
         headers: bearer(@admin_token)
    assert_response :success
    revoked = JSON.parse(response.body)
    refute revoked.key?("token")
    assert revoked.fetch("revoked_at").present?
  end

  test "requests without a token are unauthorized" do
    get "/recording_studio_api/api/v1/webhook-endpoints"
    assert_response :unauthorized
  end

  test "a non-admin token is forbidden" do
    get "/recording_studio_api/api/v1/webhook-endpoints", headers: bearer(@view_token)
    assert_response :forbidden
  end

  test "another root's endpoint is not visible" do
    foreign = create_endpoint!(@other_root, @admin, "Foreign hook")
    create_endpoint!(@root, @admin, "Local hook")

    get "/recording_studio_api/api/v1/webhook-endpoints", headers: bearer(@admin_token)
    assert_response :success
    ids = JSON.parse(response.body).fetch("records").map { |record| record.fetch("id") }
    refute_includes ids, foreign.id

    get "/recording_studio_api/api/v1/webhook-endpoints/#{foreign.id}",
        headers: bearer(@admin_token)
    assert_response :not_found
  end

  private

  def bearer(token)
    { "Authorization" => "Bearer #{token}" }
  end

  def create_user!(email)
    User.find_or_create_by!(email: email) do |user|
      user.password = "Password123!"
      user.password_confirmation = "Password123!"
    end
  end

  def bootstrap_owner!(recording, actor)
    result = RecordingStudioAccessible.bootstrap_owner_access!(
      recording: recording,
      actor: actor
    )
    raise result.error if result.failure?

    result.value
  end

  def grant_access!(recording, actor, role, manager:)
    result = RecordingStudioAccessible.grant_access(
      recording: recording,
      actor: actor,
      role: role,
      manager_actor: manager
    )
    raise result.error if result.failure?

    result.value
  end

  def issue_access_token(access_recording, name, manager: nil)
    manager ||= access_recording.recordable.actor
    Current.actor = manager
    point = access_recording.parent_recording || access_recording.root_recording
    provision = RecordingStudioApi::Services::ProvisionApiClient.call(
      access_point_recording: point,
      manager_actor: manager,
      role: access_recording.recordable.role,
      name: name
    )
    raise provision.error unless provision.success?

    token_result = RecordingStudioApi::Services::IssueOauthAccessToken.call(
      grant_type: "client_credentials",
      client_id: provision.value.fetch(:credential).oauth_client_id,
      client_secret: provision.value.fetch(:token)
    )
    raise token_result.error unless token_result.success?

    token_result.value.fetch(:access_token)
  end

  def create_endpoint!(root, actor, label)
    Current.actor = actor
    RecordingStudioWebhooks::EndpointLifecycle.create!(
      endpoint: RecordingStudioWebhooks::Endpoint.new(
        recording_studio_recording_id: root.id,
        label: label,
        provider_name: "demo",
        identity: {},
        metadata: {},
        policy_overrides: {},
        enabled: true
      ),
      actor: actor
    )
  end
end
