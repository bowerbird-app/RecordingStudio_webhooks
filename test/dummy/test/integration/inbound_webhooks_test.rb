# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class InboundWebhooksTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @webhooks_configuration = RecordingStudioWebhooks.configuration
    @original_admin_authorizer = @webhooks_configuration.admin_authorizer
    @original_admin_recording_scope = @webhooks_configuration.admin_recording_scope
    @webhooks_configuration.admin_authorizer = ->(context) { context.actor&.email == "admin@admin.com" }
    @webhooks_configuration.admin_recording_scope = ->(_context) { RecordingStudio::Recording.where(trashed_at: nil) }

    @user = User.find_or_create_by!(email: "admin@admin.com") do |user|
      user.password = "Password123!"
      user.password_confirmation = "Password123!"
    end
    workspace = Workspace.create!(name: "Webhook Workspace #{SecureRandom.hex(4)}")
    @recording = RecordingStudio.root_recording_for(workspace)
    original_access_authorizer = RecordingStudioAccessible.configuration.access_management_authorizer
    begin
      RecordingStudioAccessible.configuration.access_management_authorizer = ->(recording:, **) { recording.present? }
      RecordingStudioAccessible.grant_access(
        recording: @recording,
        actor: @user,
        role: :admin,
        manager_actor: @user
      )
    ensure
      RecordingStudioAccessible.configuration.access_management_authorizer = original_access_authorizer
    end

    @endpoint = RecordingStudioWebhooks::EndpointLifecycle.create!(
      endpoint: RecordingStudioWebhooks::Endpoint.new(
        recording_studio_recording_id: @recording.id,
        label: "Demo endpoint",
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
  end

  test "current token authenticates intake once, redacts payload, and deduplicates" do
    issuance = @endpoint.issue_token!
    token = issuance.plaintext_token
    payload = {
      id: "evt_1",
      type: "demo.received",
      token: "must-not-persist",
      action_only: "must-also-not-persist",
      name: "Ada"
    }

    post inbound_path(token), params: JSON.generate(payload), headers: intake_headers

    assert_response :accepted
    assert_equal "accepted", JSON.parse(response.body).fetch("status")
    event = @endpoint.inbound_events.find_by!(provider_event_id: "evt_1")
    assert_equal "[FILTERED]", event.payload.fetch("token")
    assert_equal "[FILTERED]", event.payload.fetch("action_only")
    assert_equal "Ada", event.payload.fetch("name")
    refute_includes event.token_snapshot.to_s, token
    assert_equal 1, event.action_plans.count

    post inbound_path(token), params: JSON.generate(payload), headers: intake_headers

    assert_response :success
    assert_equal "duplicate", JSON.parse(response.body).fetch("status")
    assert_equal 1, @endpoint.inbound_events.count
  end

  test "rotating a token invalidates the previous value and plaintext is one-time" do
    first_issuance = @endpoint.issue_token!
    first_snapshot_id = first_issuance.endpoint_token.id
    first_token = first_issuance.plaintext_token
    assert_raises(RecordingStudioWebhooks::Error) { first_issuance.plaintext_token }

    second_issuance = @endpoint.rotate_token!(actor: @user)
    second_token = second_issuance.plaintext_token

    assert_nil RecordingStudioWebhooks::EndpointToken.authenticate(plaintext: first_token)
    assert_predicate(
      RecordingStudioWebhooks::EndpointToken.authenticate(plaintext: second_token),
      :current?
    )
    revoked_snapshot = RecordingStudioWebhooks::EndpointToken
      .where(endpoint_id: @endpoint.id, digest: first_issuance.endpoint_token.digest)
      .where.not(revoked_at: nil)
      .order(:created_at)
      .last
    assert_predicate revoked_snapshot, :present?
    assert_equal @user.id.to_s, revoked_snapshot.revoked_by_actor_id
    first_token_recording = @recording.recording_for(revoked_snapshot)
    assert_equal first_token_recording.recordable_id, revoked_snapshot.id
    assert_equal first_snapshot_id, first_issuance.endpoint_token.id
    assert_includes first_token_recording.events.pluck(:action), "recording_studio_webhooks.endpoint_token.issued"
    assert_includes first_token_recording.events.pluck(:action), "recording_studio_webhooks.endpoint_token.revoked"
    assert_equal second_token, @endpoint.endpoint_tokens.order(:created_at).last.token
  end

  test "public intake returns a generic unauthorized response without exposing a credential" do
    post inbound_path("rswh_notavalidtoken"),
      params: JSON.generate(id: "evt_unauthorized", type: "demo.received"),
      headers: intake_headers

    assert_response :unauthorized
    assert_equal({ "status" => "unauthorized" }, JSON.parse(response.body))
    refute_includes response.body, "not-a-valid-token"
  end

  test "public intake rejects an unknown token without revealing routing details" do
    post "/webhooks/inbound/rswh_unknowncredential",
      params: JSON.generate(id: "evt_wrong_endpoint", type: "demo.received"),
      headers: intake_headers

    assert_response :unauthorized
    assert_equal({ "status" => "unauthorized" }, JSON.parse(response.body))
    assert_equal 0, @endpoint.inbound_events.count
  end

  test "deduplication can be disabled without discarding the provider event id" do
    @endpoint = RecordingStudioWebhooks::EndpointLifecycle.update!(
      endpoint: @endpoint,
      attributes: { policy_overrides: { deduplicate: false } },
      actor: @user
    )
    token = @endpoint.issue_token!.plaintext_token
    payload = { id: "evt_repeated", type: "demo.received" }

    2.times do
      post inbound_path(token), params: JSON.generate(payload), headers: intake_headers
      assert_response :accepted
      assert_equal "accepted", JSON.parse(response.body).fetch("status")
    end

    events = @endpoint.inbound_events.where(provider_event_id: "evt_repeated").order(:created_at)
    assert_equal 2, events.count
    assert_equal ["evt_repeated", "evt_repeated"], events.pluck(:provider_event_id)
    refute_equal events.first.deduplication_key, events.second.deduplication_key
  end

  test "page.created action creates a page recording using payload title" do
    token = @endpoint.issue_token!.plaintext_token
    title = "Test Page From Webhook"
    payload = {
      id: "evt_page_created_1",
      type: "page.created",
      data: {
        object: {
          id: "obj_123",
          status: "active",
          title: title
        }
      }
    }

    post inbound_path(token), params: JSON.generate(payload), headers: intake_headers

    assert_response :accepted
    event = @endpoint.inbound_events.find_by!(provider_event_id: "evt_page_created_1")
    plan = event.action_plans.find_by!(action_name: "demo.page_created")

    result = RecordingStudioWebhooks::ExecuteActionPlan.call(plan.id)

    assert_equal "action_succeeded", result.code
    page = Page.find_by!(title: title)
    root_recording = @endpoint.recording_studio_recording.root_recording_or_self
    assert_predicate RecordingStudio::Recording.find_by(root_recording: root_recording, recordable: page, trashed_at: nil), :present?
  end

  test "endpoint rows can coexist for the same provider and recording and empty JSON objects are valid" do
    other_workspace = Workspace.create!(name: "Other Webhook Workspace #{SecureRandom.hex(4)}")
    other_recording = RecordingStudio.root_recording_for(other_workspace)
    endpoint = RecordingStudioWebhooks::Endpoint.create!(
      recording_studio_recording: @recording,
      label: "Current endpoint",
      provider_name: "stripe",
      identity: {},
      metadata: {},
      policy_overrides: {}
    )
    duplicate = RecordingStudioWebhooks::Endpoint.new(
      recording_studio_recording: @recording,
      label: "Duplicate endpoint",
      provider_name: "stripe",
      identity: {},
      metadata: {},
      policy_overrides: {}
    )

    assert_predicate endpoint, :persisted?
    assert_predicate duplicate, :valid?

    allowed_for_other_recording = RecordingStudioWebhooks::Endpoint.new(
      recording_studio_recording: other_recording,
      label: "Other recording endpoint",
      provider_name: "stripe",
      identity: {},
      metadata: {},
      policy_overrides: {}
    )
    assert_predicate allowed_for_other_recording, :valid?

    invalid_json = RecordingStudioWebhooks::Endpoint.new(
      recording_studio_recording: other_recording,
      label: "Typed endpoint",
      provider_name: "stripe",
      identity: [],
      metadata: "not-an-object",
      policy_overrides: {}
    )

    refute_predicate invalid_json, :valid?
    assert_includes invalid_json.errors[:identity], "must be a JSON object"
    assert_includes invalid_json.errors[:metadata], "must be a JSON object"
  end

  test "endpoint lifecycle revisions create a new current endpoint row" do
    original_endpoint = @endpoint
    stable_recording = original_endpoint.recording_studio_recording
    assert_equal original_endpoint.id, stable_recording.recordable_id

    replacement = RecordingStudioWebhooks::EndpointLifecycle.update!(
      endpoint: @endpoint,
      attributes: { label: "Revised endpoint" },
      actor: @user
    )

    assert_equal "Revised endpoint", replacement.label
    refute_equal original_endpoint.id, replacement.id
    assert_equal stable_recording.id, replacement.recording_studio_recording_id
    assert_equal original_endpoint.provider_name, replacement.provider_name

    assert_equal replacement.id, stable_recording.reload.recordable_id

    current = RecordingStudioWebhooks::Endpoint.current.find_by!(
      provider_name: replacement.provider_name,
      recording_studio_recording_id: replacement.recording_studio_recording_id
    )
    assert_equal replacement.id, current.id

    assert_raises(ActiveRecord::ReadOnlyRecord) do
      RecordingStudioWebhooks::EndpointLifecycle.update!(
        endpoint: replacement,
        attributes: { provider_name: "other" },
        actor: @user
      )
    end
  end

  test "endpoint lifecycle rolls back creates and updates when audit logging fails" do
    attributes = {
      recording_studio_recording: @recording,
      label: "Audit endpoint",
      provider_name: "demo_audit",
      identity: {},
      metadata: {},
      policy_overrides: {}
    }
    failing_audit = ->(**_arguments) { raise RecordingStudioWebhooks::Error, "audit unavailable" }

    assert_no_difference -> { RecordingStudioWebhooks::Endpoint.count } do
      assert_raises(RecordingStudioWebhooks::Error) do
        with_stubbed_gateway_log_event(failing_audit) do
          RecordingStudioWebhooks::EndpointLifecycle.create!(
            endpoint: RecordingStudioWebhooks::Endpoint.new(attributes),
            actor: @user
          )
        end
      end
    end

    original_enabled = @endpoint.enabled?
    assert_raises(RecordingStudioWebhooks::Error) do
      with_stubbed_gateway_log_event(failing_audit) do
        RecordingStudioWebhooks::EndpointLifecycle.update!(
          endpoint: @endpoint,
          attributes: { enabled: !original_enabled },
          actor: @user
        )
      end
    end
    assert_equal original_enabled, @endpoint.reload.enabled?
  end

  test "temporary dispatcher failures keep an accepted action plan recoverable" do
    configuration = RecordingStudioWebhooks.configuration
    original_dispatcher = configuration.dispatcher
    configuration.dispatcher = ->(_plan_id, _wait_until = nil) { raise "queue unavailable" }
    issuance = @endpoint.issue_token!
    payload = { id: "evt_queue", type: "demo.received" }

    post inbound_path(issuance.plaintext_token), params: JSON.generate(payload), headers: intake_headers

    assert_response :accepted
    plan = @endpoint.inbound_events.find_by!(provider_event_id: "evt_queue").action_plans.first.reload
    assert_predicate plan, :retrying?
    refute_predicate plan, :terminal?

    configuration.dispatcher = ->(_plan_id, _wait_until = nil) { true }
    results = RecordingStudioWebhooks::RecoverActionPlans.call(now: plan.next_attempt_at + 1.second)

    assert_equal "action_plan_dispatched", results.first.code
    refute_predicate plan.reload, :terminal?
  ensure
    configuration.dispatcher = original_dispatcher
  end

  test "authorized administrators can use the non-persisting action sandbox" do
    sign_in @user

    post sandbox_path, params: {
      sandbox: {
        endpoint_id: @endpoint.id,
        provider_name: @endpoint.provider_name,
        event_type: "demo.received",
        headers_json: JSON.generate({ authorization: "Bearer invalid-token", "x-webhook-timestamp": Time.current.iso8601 }),
        payload: JSON.generate(token: "never-render-this", id: "sample")
      }
    }

    assert_response :success
    assert_includes response.body, "demo.received"
    assert_equal 0, @endpoint.inbound_events.count
  end

  test "authorized administrators can use dummy webhook tester route" do
    sign_in @user
    token = @endpoint.issue_token!.plaintext_token
    title = "Tester Page"

    post "/dummy_webhook_tester", params: {
      tester: {
        endpoint_input: "https://example.test/webhooks/inbound/#{token}",
        headers_json: JSON.generate({ "content-type" => "application/json" }),
        payload_json: JSON.generate(
          {
            id: "evt_tester_1",
            type: "page.created",
            data: {
              object: {
                id: "obj_abc",
                status: "active",
                title: title
              }
            }
          }
        )
      }
    }

    assert_response :success
    assert_includes response.body, "accepted"
    assert_includes response.body, "action_succeeded"
    assert_predicate Page.find_by(title: title), :present?
  end

  test "authorized administrators can open admin webhooks root and provider pages" do
    sign_in @user

    get "/admin/webhooks"
    assert_redirected_to "/admin/sections/admin_webhooks"

    follow_redirect!
    assert_response :success
    assert_includes response.body, "Admin Webhooks"
    assert_includes response.body, "Webhook traffic"

    get "/admin/webhooks/providers/demo"
    assert_response :success
    assert_includes response.body, "Provider-linked actions and endpoints."
  end

  test "authorized administrators can inspect native webhook traffic with filters, chart, and table" do
    token = @endpoint.issue_token!.plaintext_token
    post inbound_path(token), params: JSON.generate(id: "evt_traffic_1", type: "demo.received"), headers: intake_headers
    assert_response :accepted
    assert_equal 1, @endpoint.inbound_events.where(provider_event_id: "evt_traffic_1").count

    sign_in @user
    get "/admin/sections/admin_webhooks"
    assert_response :success

    get "/admin/screens/webhook_traffic", params: {
      provider: "demo",
      endpoint: @endpoint.label,
      group_by: "week"
    }

    assert_response :success
    assert_includes response.body, "Webhook traffic"
    assert_includes response.body, "Date range"
    assert_includes response.body, "Group by"
    assert_includes response.body, "Provider"
    assert_includes response.body, "Endpoint"

    get "/admin/screens/webhook_traffic/chart", params: { provider: "demo", endpoint: @endpoint.label, group_by: "week" }
    assert_response :success
    assert_includes response.body, "Inbound events"

    get "/admin/screens/webhook_traffic/table", params: { provider: "demo", endpoint: @endpoint.label }
    assert_response :success
    assert_includes response.body, "Inbound events"
  end

  test "authorized administrators can filter events by token value" do
    sign_in @user
    first_token = @endpoint.issue_token!.plaintext_token

    post inbound_path(first_token), params: JSON.generate(id: "evt_filter_token_1", type: "demo.received"), headers: intake_headers
    assert_response :accepted

    second_token = @endpoint.rotate_token!(actor: @user).plaintext_token
    post inbound_path(second_token), params: JSON.generate(id: "evt_filter_token_2", type: "demo.received"), headers: intake_headers
    assert_response :accepted

    get "/admin/webhooks/events", params: { endpoint_token: first_token }

    assert_response :success
    assert_includes response.body, first_token
    refute_includes response.body, second_token
  end

  test "authorized administrators can list endpoints with stable recording ownership" do
    sign_in @user
    token = @endpoint.issue_token!.plaintext_token

    get "/admin/webhooks/endpoints"

    assert_response :success
    assert_includes response.body, @endpoint.label
    assert_includes response.body, "/webhooks/inbound/#{token}"
    refute_includes response.body, "/webhooks/inbound/rswh_..."
  end

  test "authorized administrators can disable endpoints via autosave switch" do
    sign_in @user
    original_endpoint = @endpoint

    patch "/admin/webhooks/endpoints/#{@endpoint.id}", params: {
      auto_save: "1",
      endpoint: { enabled: "0" }
    }

    assert_response :redirect
    assert_includes response.location, "/admin/webhooks/endpoints/"
    assert_includes response.location, "/edit"

    current_endpoint = RecordingStudioWebhooks::Endpoint.current.find_by!(
      provider_name: original_endpoint.provider_name,
      recording_studio_recording_id: original_endpoint.recording_studio_recording_id
    )
    refute_predicate current_endpoint, :enabled?
  end

  test "stale endpoint show URL resolves to current endpoint status" do
    sign_in @user

    stale_endpoint = @endpoint
    disabled_endpoint = RecordingStudioWebhooks::EndpointLifecycle.update!(
      endpoint: stale_endpoint,
      attributes: { enabled: false },
      actor: @user
    )
    RecordingStudioWebhooks::EndpointLifecycle.update!(
      endpoint: disabled_endpoint,
      attributes: { enabled: true },
      actor: @user
    )
    current_endpoint = RecordingStudioWebhooks::Endpoint.current.find_by!(
      provider_name: stale_endpoint.provider_name,
      recording_studio_recording_id: stale_endpoint.recording_studio_recording_id
    )

    get "/admin/webhooks/endpoints/#{stale_endpoint.id}"

    assert_response :success
    assert_includes response.body, "/admin/webhooks/endpoints/#{current_endpoint.id}/edit"
    refute_includes response.body, "/admin/webhooks/endpoints/#{stale_endpoint.id}/edit"
  end

  test "endpoint event inspect works after endpoint is revised" do
    sign_in @user
    token = @endpoint.issue_token!.plaintext_token

    post inbound_path(token), params: JSON.generate(id: "evt_stale_event_1", type: "demo.received"), headers: intake_headers
    assert_response :accepted
    event = @endpoint.inbound_events.find_by!(provider_event_id: "evt_stale_event_1")

    current_endpoint = RecordingStudioWebhooks::EndpointLifecycle.update!(
      endpoint: @endpoint,
      attributes: { enabled: false },
      actor: @user
    )

    get "/admin/webhooks/endpoints/#{current_endpoint.id}/events/#{event.id}"

    assert_response :success
    assert_includes response.body, "demo.received"
  end

  test "token history shows only latest token snapshot rows" do
    sign_in @user

    first_issuance = @endpoint.issue_token!
    first_prefix = first_issuance.endpoint_token.prefix
    @endpoint.rotate_token!(actor: @user)

    get "/admin/webhooks/endpoints/#{@endpoint.id}/tokens"

    assert_response :success
    assert_equal 1, response.body.scan(first_prefix).length
    assert_match(/<td class=\"p-2\">[A-Z][a-z]{2} \d{2} \d{4}<\/td>/, response.body)
  end

  test "creating an endpoint auto-issues a token and shows one-time disclosure" do
    sign_in @user
    label = "Auto token endpoint"
    other_workspace = Workspace.create!(name: "Auto Token Workspace #{SecureRandom.hex(4)}")
    other_recording = RecordingStudio.root_recording_for(other_workspace)

    post "/admin/webhooks/endpoints", params: {
      endpoint: {
        recording_studio_recording_id: other_recording.id,
        label: label,
        provider_name: "demo",
        enabled: "1",
        identity_json: JSON.generate({ "origin" => "test" }),
        metadata_json: JSON.generate({}),
        policy_json: JSON.generate({})
      }
    }

    assert_response :created
    assert_includes response.body, "Webhook endpoint ready"
    assert_includes response.body, "rswh_"
    endpoint = RecordingStudioWebhooks::Endpoint.current.find_by!(provider_name: "demo", label: label)
    assert_includes response.body, "/webhooks/inbound/rswh_"

    assert_equal label, endpoint.label
    assert_equal 1, endpoint.endpoint_tokens.count
    assert_predicate endpoint.endpoint_tokens.first, :current?
  end

  test "administration fails closed when its authorizer is absent" do
    configuration = RecordingStudioWebhooks.configuration
    original_authorizer = configuration.admin_authorizer
    configuration.admin_authorizer = nil

    get "/admin/webhooks/endpoints"

    assert_response :not_found
  ensure
    configuration.admin_authorizer = original_authorizer
  end

  private

  def inbound_path(token)
    "/webhooks/inbound/#{token}"
  end

  def sandbox_path
    "/admin/webhooks/webhook_sandbox"
  end

  def intake_headers
    {
      "CONTENT_TYPE" => "application/json"
    }
  end

  def with_stubbed_gateway_log_event(callable)
    gateway = RecordingStudioWebhooks::RecordingStudioGateway
    singleton = class << gateway; self; end
    original = gateway.method(:log_event!)
    singleton.define_method(:log_event!, &callable)
    yield
  ensure
    singleton.define_method(:log_event!, original) if singleton && original
  end

  def endpoint_health_counts(body)
    match = body.match(/Endpoint health.*?>(\d+)\/(\d+)<.*?enabled \/ total · (\d+) paused/m)
    assert_predicate match, :present?

    [match[1].to_i, match[2].to_i, match[3].to_i]
  end
end
