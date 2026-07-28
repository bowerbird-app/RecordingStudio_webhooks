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

  test "temporary dispatcher failures keep an accepted action plan recoverable" do
    configuration = RecordingStudioWebhooks.configuration
    original_dispatcher = configuration.dispatcher
    configuration.dispatcher = ->(_plan_id, _wait_until = nil) { raise "queue unavailable" }
    issuance = @endpoint.issue_token!
    payload = { id: "evt_queue", type: "demo.received" }

    post inbound_path, params: JSON.generate(payload), headers: intake_headers(issuance.plaintext_token)

    assert_response :accepted
    plan = @endpoint.inbound_events.find_by!(provider_event_id: "evt_queue").action_plans.first.reload
    assert_predicate plan, :retry_scheduled?
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
        event_type: "demo.received",
        payload: JSON.generate(token: "never-render-this", id: "sample")
      }
    }

    assert_response :success
    assert_includes response.body, "demo.received"
    assert_includes response.body, "[FILTERED]"
    refute_includes response.body, "never-render-this"
    assert_equal 0, @endpoint.inbound_events.count
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
    "/webhooks/admin/endpoints/#{@endpoint.id}/sandbox"
  end

  def intake_headers(token)
    {
      "CONTENT_TYPE" => "application/json",
      "HTTP_AUTHORIZATION" => "Bearer " + token
    }
  end
end
