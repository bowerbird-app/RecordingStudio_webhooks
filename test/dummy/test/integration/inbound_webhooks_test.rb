# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class InboundWebhooksTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.find_or_create_by!(email: "admin@admin.com") do |user|
      user.password = "Password123!"
      user.password_confirmation = "Password123!"
    end
    workspace = Workspace.create!(name: "Webhook Workspace #{SecureRandom.hex(4)}")
    @recording = RecordingStudio.root_recording_for(workspace)
    @endpoint = RecordingStudioWebhooks::Endpoint.create!(
      recording_studio_recording_id: @recording.id,
      provider_name: "demo",
      identity_key: "demo-#{SecureRandom.hex(4)}",
      identity: { "test" => true },
      metadata: {},
      policy_overrides: {}
    )
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

    post inbound_path, params: JSON.generate(payload), headers: intake_headers(token)

    assert_response :accepted
    assert_equal "accepted", JSON.parse(response.body).fetch("status")
    event = @endpoint.inbound_events.find_by!(provider_event_id: "evt_1")
    assert_equal "[FILTERED]", event.payload.fetch("token")
    assert_equal "[FILTERED]", event.payload.fetch("action_only")
    assert_equal "Ada", event.payload.fetch("name")
    refute_includes event.token_snapshot.to_s, token
    assert_equal 1, event.action_plans.count

    post inbound_path, params: JSON.generate(payload), headers: intake_headers(token)

    assert_response :success
    assert_equal "duplicate", JSON.parse(response.body).fetch("status")
    assert_equal 1, @endpoint.inbound_events.count
  end

  test "rotating a token invalidates the previous value and plaintext is one-time" do
    first_issuance = @endpoint.issue_token!
    first_token = first_issuance.plaintext_token
    assert_raises(RecordingStudioWebhooks::Error) { first_issuance.plaintext_token }

    second_issuance = @endpoint.rotate_token!
    second_token = second_issuance.plaintext_token

    assert_nil RecordingStudioWebhooks::EndpointToken.authenticate(endpoint: @endpoint, plaintext: first_token)
    assert_predicate(
      RecordingStudioWebhooks::EndpointToken.authenticate(endpoint: @endpoint, plaintext: second_token),
      :current?
    )
    refute_includes @endpoint.endpoint_tokens.order(:created_at).last.attributes.values, second_token
  end

  test "public intake returns a generic unauthorized response without exposing a credential" do
    post inbound_path,
      params: JSON.generate(id: "evt_unauthorized", type: "demo.received"),
      headers: intake_headers("not-a-valid-token")

    assert_response :unauthorized
    assert_equal({ "status" => "unauthorized" }, JSON.parse(response.body))
    refute_includes response.body, "not-a-valid-token"
  end

  test "public intake binds a credential to the endpoint identity in its route" do
    token = @endpoint.issue_token!.plaintext_token

    post "/webhooks/inbound/demo/missing-endpoint",
      params: JSON.generate(id: "evt_wrong_endpoint", type: "demo.received"),
      headers: intake_headers(token)

    assert_response :not_found
    assert_equal({ "status" => "not_found" }, JSON.parse(response.body))
    assert_equal 0, @endpoint.inbound_events.count
  end

  test "deduplication can be disabled without discarding the provider event id" do
    @endpoint.update!(policy_overrides: { deduplicate: false })
    token = @endpoint.issue_token!.plaintext_token
    payload = { id: "evt_repeated", type: "demo.received" }

    2.times do
      post inbound_path, params: JSON.generate(payload), headers: intake_headers(token)
      assert_response :accepted
      assert_equal "accepted", JSON.parse(response.body).fetch("status")
    end

    events = @endpoint.inbound_events.where(provider_event_id: "evt_repeated").order(:created_at)
    assert_equal 2, events.count
    assert_equal ["evt_repeated", "evt_repeated"], events.pluck(:provider_event_id)
    refute_equal events.first.deduplication_key, events.second.deduplication_key
  end

  test "endpoint identities are global per provider and empty JSON objects are valid" do
    other_workspace = Workspace.create!(name: "Other Webhook Workspace #{SecureRandom.hex(4)}")
    other_recording = RecordingStudio.root_recording_for(other_workspace)
    identity_key = "global-#{SecureRandom.hex(4)}"
    endpoint = RecordingStudioWebhooks::Endpoint.create!(
      recording_studio_recording: @recording,
      provider_name: "demo",
      identity_key: identity_key,
      identity: {},
      metadata: {},
      policy_overrides: {}
    )
    duplicate = RecordingStudioWebhooks::Endpoint.new(
      recording_studio_recording: other_recording,
      provider_name: "demo",
      identity_key: identity_key,
      identity: {},
      metadata: {},
      policy_overrides: {}
    )

    assert_predicate endpoint, :persisted?
    refute_predicate duplicate, :valid?
    assert_includes duplicate.errors[:identity_key], "has already been taken"

    invalid_json = RecordingStudioWebhooks::Endpoint.new(
      recording_studio_recording: other_recording,
      provider_name: "demo",
      identity_key: "typed-#{SecureRandom.hex(4)}",
      identity: [],
      metadata: "not-an-object",
      policy_overrides: {}
    )

    refute_predicate invalid_json, :valid?
    assert_includes invalid_json.errors[:identity], "must be a JSON object"
    assert_includes invalid_json.errors[:metadata], "must be a JSON object"
  end

  test "endpoint identity key is editable but provider and recording linkage remain immutable" do
    original_key = @endpoint.identity_key
    updated_key = "renamed-#{SecureRandom.hex(4)}"

    RecordingStudioWebhooks::EndpointLifecycle.update!(
      endpoint: @endpoint,
      attributes: { identity_key: updated_key },
      actor: @user
    )

    assert_equal updated_key, @endpoint.reload.identity_key
    refute_equal original_key, @endpoint.identity_key

    assert_raises(ActiveRecord::ReadOnlyRecord) do
      RecordingStudioWebhooks::EndpointLifecycle.update!(
        endpoint: @endpoint,
        attributes: { provider_name: "other" },
        actor: @user
      )
    end
  end

  test "endpoint lifecycle rolls back creates and updates when audit logging fails" do
    attributes = {
      recording_studio_recording: @recording,
      provider_name: "demo",
      identity_key: "audit-#{SecureRandom.hex(4)}",
      identity: {},
      metadata: {},
      policy_overrides: {}
    }
    failing_audit = ->(**_arguments) { raise RecordingStudioWebhooks::Error, "audit unavailable" }

    assert_no_difference -> { RecordingStudioWebhooks::Endpoint.count } do
      assert_raises(RecordingStudioWebhooks::Error) do
        RecordingStudioWebhooks::RecordingStudioGateway.stub(:log_event!, failing_audit) do
          RecordingStudioWebhooks::EndpointLifecycle.create!(
            endpoint: RecordingStudioWebhooks::Endpoint.new(attributes),
            actor: @user
          )
        end
      end
    end

    original_enabled = @endpoint.enabled?
    assert_raises(RecordingStudioWebhooks::Error) do
      RecordingStudioWebhooks::RecordingStudioGateway.stub(:log_event!, failing_audit) do
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

    post inbound_path, params: JSON.generate(payload), headers: intake_headers(issuance.plaintext_token)

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
    assert_includes response.body, "[FILTERED]"
    refute_includes response.body, "never-render-this"
    assert_equal 0, @endpoint.inbound_events.count
  end

  test "authorized administrators can open admin webhooks root and provider pages" do
    sign_in @user

    get "/webhooks/admin"
    assert_response :success
    assert_includes response.body, "Admin Webhooks"

    get "/webhooks/admin/providers/demo"
    assert_response :success
    assert_includes response.body, "Provider definition"
  end

  test "authorized administrators can list endpoints with stable recording ownership" do
    sign_in @user

    get "/webhooks/admin/endpoints"

    assert_response :success
    assert_includes response.body, @endpoint.identity_key
  end

  test "creating an endpoint auto-issues a token and shows one-time disclosure" do
    sign_in @user
    identity_key = "auto-token-#{SecureRandom.hex(4)}"

    post "/webhooks/admin/endpoints", params: {
      endpoint: {
        recording_studio_recording_id: @recording.id,
        provider_name: "demo",
        identity_key: identity_key,
        enabled: "1",
        identity_json: JSON.generate({ "origin" => "test" }),
        metadata_json: JSON.generate({}),
        policy_json: JSON.generate({})
      }
    }

    assert_response :created
    assert_includes response.body, "Copy this token now"
    assert_includes response.body, "rswh_"
    assert_includes response.body, "/webhooks/inbound/demo/#{identity_key}"

    endpoint = RecordingStudioWebhooks::Endpoint.find_by!(provider_name: "demo", identity_key: identity_key)
    assert_equal 1, endpoint.endpoint_tokens.count
    assert_predicate endpoint.endpoint_tokens.first, :current?
  end

  test "administration fails closed when its authorizer is absent" do
    configuration = RecordingStudioWebhooks.configuration
    original_authorizer = configuration.admin_authorizer
    configuration.admin_authorizer = nil

    get "/webhooks/admin/endpoints"

    assert_response :not_found
  ensure
    configuration.admin_authorizer = original_authorizer
  end

  private

  def inbound_path
    "/webhooks/inbound/demo/#{@endpoint.identity_key}"
  end

  def sandbox_path
    "/webhooks/admin/webhook_sandbox"
  end

  def intake_headers(token)
    {
      "CONTENT_TYPE" => "application/json",
      "HTTP_AUTHORIZATION" => "Bearer " + token
    }
  end
end
