# frozen_string_literal: true

require "test_helper"

class WebhookMetricsApiTest < ActionDispatch::IntegrationTest
  OPERATIONS_ROOT = "/recording_studio_api/apis/operations/v1"
  PUBLIC_ROOT = "/recording_studio_api/api/v1"

  setup do
    @staff = User.create!(
      email: "metrics-staff-#{SecureRandom.hex(4)}@example.com",
      password: "Password",
      password_confirmation: "Password"
    )
    Current.actor = @staff
    @workspace = Workspace.create!(name: "Metrics #{SecureRandom.hex(4)}")
    @root = RecordingStudio.root_recording_for(@workspace)
    @admin_root = RecordingStudio.root_recording_for(AdminRoot.find_or_create_by!(name: "Admin"))
    grant!(@admin_root, @staff, :admin)
    bootstrap_owner!(@root, @staff)

    seed_webhooks!

    @staff_operations_token = provision_token(
      access_point: @admin_root,
      actor: @staff,
      role: :edit,
      name: "Staff operations metrics #{SecureRandom.hex(4)}",
      api: :operations
    )
    @workspace_operations_token = provision_token(
      access_point: @root,
      actor: @staff,
      role: :edit,
      name: "Workspace operations metrics #{SecureRandom.hex(4)}",
      api: :operations
    )
    @public_token = provision_token(
      access_point: @root,
      actor: @staff,
      role: :view,
      name: "Public metrics #{SecureRandom.hex(4)}"
    )
    Current.actor = nil
  end

  teardown do
    Current.actor = nil
  end

  test "operations staff token reads webhook event, attempt, and endpoint metrics" do
    get "#{OPERATIONS_ROOT}/metrics/webhook_events/over_time",
        params: { interval: "day" },
        headers: auth(@staff_operations_token),
        as: :json
    assert_response :success
    opened = timeseries_counts(response.parsed_body)
    assert_equal events_received_between(Time.utc(2026, 10, 7), Time.utc(2026, 10, 8)), opened["2026-10-07"]
    assert_equal events_received_between(Time.utc(2026, 10, 8), Time.utc(2026, 10, 9)), opened["2026-10-08"]
    assert_operator opened["2026-10-07"], :>=, 1
    assert_operator opened["2026-10-08"], :>=, 2

    get "#{OPERATIONS_ROOT}/metrics/webhook_events/by_provider",
        headers: auth(@staff_operations_token),
        as: :json
    assert_response :success
    provider_counts = breakdown_counts(response.parsed_body)
    RecordingStudioWebhooks::InboundEvent.distinct.pluck(:provider_name).each do |provider|
      assert_equal RecordingStudioWebhooks::InboundEvent.where(provider_name: provider).count,
                   provider_counts[provider].to_i
    end

    get "#{OPERATIONS_ROOT}/metrics/webhook_attempts/by_status",
        headers: auth(@staff_operations_token),
        as: :json
    assert_response :success
    status_counts = breakdown_counts(response.parsed_body)
    RecordingStudioWebhooks::ActionAttempt::STATUSES.each do |status|
      assert_equal RecordingStudioWebhooks::ActionAttempt.where(status: status).count, status_counts[status].to_i
    end

    get "#{OPERATIONS_ROOT}/metrics/webhook_endpoints/enabled",
        headers: auth(@staff_operations_token),
        as: :json
    assert_response :success
    enabled = RecordingStudioWebhooks::Endpoint.current.where(enabled: true).count
    assert_equal enabled, response.parsed_body.fetch("value")
    assert_operator RecordingStudioWebhooks::Endpoint.current.where(enabled: false).count, :>=, 1
  end

  test "metrics index lists webhook metrics" do
    get "#{OPERATIONS_ROOT}/metrics", headers: auth(@staff_operations_token), as: :json

    assert_response :success
    identifiers = response.parsed_body.fetch("metrics").map { |row| row.fetch("identifier") }
    %w[
      webhook_events.over_time
      webhook_events.by_provider
      webhook_attempts.by_status
      webhook_endpoints.enabled
    ].each { |identifier| assert_includes identifiers, identifier }
  end

  test "non-admin operations token is denied webhook metrics" do
    get "#{OPERATIONS_ROOT}/metrics/webhook_events/over_time",
        headers: auth(@workspace_operations_token),
        as: :json
    assert_response :forbidden

    get "#{OPERATIONS_ROOT}/metrics/webhook_endpoints/enabled",
        headers: auth(@workspace_operations_token),
        as: :json
    assert_response :forbidden

    get "#{OPERATIONS_ROOT}/metrics", headers: auth(@workspace_operations_token), as: :json
    assert_response :success
    identifiers = response.parsed_body.fetch("metrics").map { |row| row.fetch("identifier") }
    refute_includes identifiers, "webhook_events.over_time"
    refute_includes identifiers, "webhook_endpoints.enabled"
  end

  test "public API token is denied operations webhook metrics" do
    get "#{OPERATIONS_ROOT}/metrics/webhook_events/over_time",
        headers: auth(@public_token),
        as: :json
    assert_response :unauthorized

    get "#{OPERATIONS_ROOT}/metrics/webhook_endpoints/enabled",
        headers: auth(@public_token),
        as: :json
    assert_response :unauthorized

    get "#{PUBLIC_ROOT}/metrics/webhook_endpoints/enabled",
        headers: auth(@public_token),
        as: :json
    assert_includes [404, 401, 403], response.status
  end

  private

  def seed_webhooks!
    demo = create_endpoint!("demo", "Metrics demo #{SecureRandom.hex(4)}", enabled: true)
    other = create_endpoint!("billing", "Metrics billing #{SecureRandom.hex(4)}", enabled: true)
    create_endpoint!("demo", "Metrics disabled #{SecureRandom.hex(4)}", enabled: false)

    demo_token = demo.issue_token!(actor: @staff).endpoint_token
    other_token = other.issue_token!(actor: @staff).endpoint_token

    travel_to Time.utc(2026, 10, 7, 12) do
      event = create_event!(demo, demo_token, "invoice.created")
      create_attempt!(event, "demo.record", "succeeded")
    end
    travel_to Time.utc(2026, 10, 8, 9) do
      first = create_event!(demo, demo_token, "invoice.paid")
      create_attempt!(first, "demo.record", "failed")
      second = create_event!(other, other_token, "invoice.paid")
      create_attempt!(second, "billing.record", "pending")
    end
  end

  def create_endpoint!(provider_name, label, enabled:)
    RecordingStudioWebhooks::EndpointLifecycle.create!(
      endpoint: RecordingStudioWebhooks::Endpoint.new(
        recording_studio_recording_id: @root.id,
        provider_name: provider_name,
        label: label,
        identity: {},
        metadata: {},
        policy_overrides: {},
        enabled: enabled
      ),
      actor: @staff
    )
  end

  def create_event!(endpoint, token, event_type)
    RecordingStudioWebhooks::InboundEvent.create!(
      endpoint: endpoint,
      endpoint_token: token,
      provider_name: endpoint.provider_name,
      event_type: event_type,
      provider_event_id: "evt_#{SecureRandom.hex(6)}",
      payload_digest: SecureRandom.hex(16),
      deduplication_key: "event:#{SecureRandom.uuid}",
      payload: { "type" => event_type },
      provenance: { "request_id" => SecureRandom.uuid },
      endpoint_snapshot: endpoint.snapshot,
      token_snapshot: token.snapshot,
      policy_snapshot: { "values" => RecordingStudioWebhooks::Policy.default.to_h },
      received_at: Time.current,
      status: "accepted"
    )
  end

  def create_attempt!(event, action_name, status)
    event.action_attempts.create!(
      action_name: action_name,
      execution_position: 0,
      status: status,
      attempts: status == "pending" ? 0 : 1,
      completed_at: %w[succeeded failed skipped cancelled].include?(status) ? Time.current : nil,
      last_error: status == "failed" ? "action_execution_failed" : nil,
      endpoint_snapshot: event.endpoint_snapshot,
      token_snapshot: event.token_snapshot,
      policy_snapshot: event.policy_snapshot,
      action_snapshot: { "name" => action_name },
      attempt_history: []
    )
  end

  def events_received_between(start_at, end_at)
    RecordingStudioWebhooks::InboundEvent.where(received_at: start_at...end_at).count
  end

  def breakdown_counts(payload)
    payload.fetch("data").to_h { |row| [row.fetch("key").to_s, row.fetch("value")] }
  end

  def timeseries_counts(payload)
    payload.fetch("data").to_h { |row| [row.fetch("date").to_s, row.fetch("value")] }
  end

  def auth(token)
    { "Authorization" => "Bearer #{token}", "Accept" => "application/json" }
  end

  def provision_token(access_point:, actor:, role:, name:, api: :public)
    result = RecordingStudioApi::Services::ProvisionApiClient.call(
      access_point_recording: access_point,
      manager_actor: actor,
      role: role,
      name: name,
      api: api
    )
    raise result.error unless result.success?

    payload = result.value
    token_result = RecordingStudioApi::Services::IssueOauthAccessToken.call(
      grant_type: "client_credentials",
      client_id: payload.fetch(:credential).oauth_client_id,
      client_secret: payload.fetch(:token),
      api: api
    )
    raise token_result.error unless token_result.success?

    token_result.value.fetch(:access_token)
  end

  def bootstrap_owner!(recording, actor)
    result = RecordingStudioAccessible.bootstrap_owner_access!(
      recording: recording,
      actor: actor
    )
    raise result.error if result.failure?
  end

  def grant!(recording, actor, role)
    return if RecordingStudioAccessible.authorized?(actor: actor, recording: recording, role: role)

    original = RecordingStudioAccessible.configuration.access_management_authorizer
    RecordingStudioAccessible.configuration.access_management_authorizer = ->(**) { true }
    result = RecordingStudioAccessible.grant_access(
      recording: recording,
      actor: actor,
      role: role,
      manager_actor: @staff
    )
    raise result.error if result.failure?
  ensure
    RecordingStudioAccessible.configuration.access_management_authorizer = original
  end
end
