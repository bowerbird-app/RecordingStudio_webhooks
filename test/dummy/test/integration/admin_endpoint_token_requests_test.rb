# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"
require_relative "../support/webhook_admin_examples"

class AdminEndpointTokenRequestsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include WebhookAdminExamples

  setup do
    setup_webhook_admin!
    sign_in @user
  end

  teardown { teardown_webhook_admin! }

  test "endpoint index keeps the query string and new renders the form" do
    get "/admin/webhooks/endpoints", params: { provider: "demo" }

    assert_redirected_to "/admin/screens/endpoints?provider=demo"

    get "/admin/webhooks/endpoints/new"
    assert_response :success
    assert_includes response.body, "New webhook endpoint"
    assert_includes response.body, "demo"
  end

  test "creating an endpoint rejects an unknown provider and invalid JSON objects" do
    post "/admin/webhooks/endpoints", params: endpoint_params(provider_name: "not_registered")

    assert_response :unprocessable_entity
    assert_includes response.body, "Choose a registered provider."
    assert_nil RecordingStudioWebhooks::Endpoint.find_by(label: "Rejected endpoint")

    post "/admin/webhooks/endpoints", params: endpoint_params(identity_json: "[]")
    assert_response :unprocessable_entity
    assert_includes response.body, "Identity must be a JSON object."

    post "/admin/webhooks/endpoints", params: endpoint_params(metadata_json: "[]")
    assert_response :unprocessable_entity
    assert_includes response.body, "Metadata must be a JSON object."

    post "/admin/webhooks/endpoints", params: endpoint_params(policy_json: "{")
    assert_response :unprocessable_entity
    assert_includes response.body, "Policy must be a JSON object."
  end

  test "creating an endpoint fails when the recording is missing or the label is too long" do
    post "/admin/webhooks/endpoints", params: endpoint_params(
      recording_studio_recording_id: SecureRandom.uuid
    )
    assert_response :not_found

    sign_in @user
    post "/admin/webhooks/endpoints", params: endpoint_params(label: "L" * 300)
    assert_response :unprocessable_entity
    assert_includes response.body, "too long"
    assert_nil RecordingStudioWebhooks::Endpoint.current.find_by(label: "L" * 300)
  end

  test "updating an endpoint autosaves to a safe return path and reports validation errors" do
    patch "/admin/webhooks/endpoints/#{@endpoint.id}", params: {
      auto_save: "1",
      return_to: "/admin/screens/tokens",
      endpoint: { enabled: "0" }
    }

    assert_redirected_to "/admin/screens/tokens"
    refute_predicate current_endpoint, :enabled?

    patch "/admin/webhooks/endpoints/#{@endpoint.id}", params: {
      auto_save: "1",
      return_to: "//evil.example/phish",
      endpoint: { enabled: "1", label: "Renamed coverage endpoint" }
    }
    assert_redirected_to "/admin/screens/endpoints"
    assert_equal "Renamed coverage endpoint", current_endpoint.label

    patch "/admin/webhooks/endpoints/#{@endpoint.id}", params: {
      endpoint: { label: "N" * 300 }
    }
    assert_redirected_to "/admin/screens/endpoints"
    assert_includes flash[:alert].to_s, "too long"
    assert_equal "Renamed coverage endpoint", current_endpoint.label
  end

  test "a view-only authorizer can open the form and cannot create an endpoint" do
    @webhooks_configuration.admin_authorizer = ->(context) { context.permission == :view }

    get "/admin/webhooks/endpoints/new"
    assert_response :success

    post "/admin/webhooks/endpoints", params: endpoint_params(label: "Should not exist")
    assert_response :not_found
    assert_nil RecordingStudioWebhooks::Endpoint.find_by(label: "Should not exist")
  end

  test "authorizer call styles and a failing recording scope stay closed or open as answered" do
    @webhooks_configuration.admin_authorizer = ->(**kwargs) { kwargs[:actor]&.email == "admin@admin.com" }
    get "/admin/webhooks/providers"
    assert_response :success

    @webhooks_configuration.admin_authorizer = ->(actor:) { actor&.email == "admin@admin.com" }
    get "/admin/webhooks/providers"
    assert_response :success

    @webhooks_configuration.admin_authorizer = -> { true }
    @webhooks_configuration.admin_recording_scope = ->(_context) { [@recording] }
    get "/admin/webhooks/endpoints/new"
    assert_response :success

    @webhooks_configuration.admin_recording_scope = ->(_context) { [@recording.id] }
    get "/admin/webhooks/endpoints/new"
    assert_response :success

    @webhooks_configuration.admin_recording_scope = ->(_context) { raise "scope unavailable" }
    get "/admin/webhooks/providers"
    assert_response :success

    @webhooks_configuration.admin_authorizer = ->(_context) { raise "authorizer unavailable" }
    get "/admin/webhooks/providers"
    assert_response :not_found
  end

  test "nested token history issues a token once and rejects bad expiration or metadata" do
    expires_at = 2.days.from_now.iso8601
    post "/admin/webhooks/endpoints/#{@endpoint.id}/tokens", params: {
      endpoint_token: { expires_at: expires_at, metadata_json: JSON.generate("purpose" => "coverage") }
    }

    assert_response :created
    assert_includes response.headers["Cache-Control"].to_s, "no-store"
    assert_includes response.body, "Copy this token now"
    issued = response.body[/\brswh_[A-Za-z0-9_-]+/]
    assert_predicate issued, :present?
    stored = RecordingStudioWebhooks::EndpointToken.authenticate(plaintext: issued)
    assert_equal "coverage", stored.metadata.fetch("purpose")
    refute_includes stored.attributes.values.map(&:to_s), issued

    post "/admin/webhooks/endpoints/#{@endpoint.id}/tokens", params: {
      endpoint_token: { metadata_json: "[]" }
    }
    assert_response :unprocessable_entity
    assert_includes response.body, "The token could not be issued."

    post "/admin/webhooks/endpoints/#{@endpoint.id}/tokens", params: {
      endpoint_token: { expires_at: 2.days.ago.iso8601 }
    }
    assert_response :unprocessable_entity

    delete "/admin/webhooks/endpoints/#{@endpoint.id}/tokens/#{SecureRandom.uuid}"
    assert_response :not_found
  end

  test "global token issuance rejects a missing endpoint and a past expiration" do
    post "/admin/webhooks/tokens", params: { token_issuance: { provider_name: "demo" } }
    assert_response :unprocessable_entity
    assert_includes response.body, "Choose a valid endpoint."

    post "/admin/webhooks/tokens", params: {
      token_issuance: { provider_name: "demo", endpoint_id: @endpoint.id, expires_at: 1.day.ago.iso8601 }
    }
    assert_response :unprocessable_entity
    assert_includes response.body, "The token could not be issued."

    get "/admin/webhooks/tokens/new", params: { provider: "not-a-provider" }
    assert_response :success
    assert_includes response.body, @endpoint.label
  end

  test "event filters ignore a bad time and can select an execution mode" do
    token = @endpoint.issue_token!.plaintext_token
    post "/webhooks/inbound/#{token}",
      params: JSON.generate(id: "evt_filter_1", type: "demo.received"),
      headers: { "CONTENT_TYPE" => "application/json" }
    assert_response :accepted

    get "/admin/webhooks/events", params: {
      provider_name: "demo",
      endpoint_id: @endpoint.id,
      endpoint_token: "https://example.test/webhooks/inbound/#{token}?x=1",
      event_type: "demo.received",
      status: "planned",
      execution_mode: "independent",
      from: "not-a-time",
      to: Time.current.iso8601
    }

    assert_response :success
    assert_includes response.body, "demo.received"
  end

  test "missing action attempts are not found" do
    get "/admin/webhooks/attempts/#{SecureRandom.uuid}"
    assert_response :not_found

    token = @endpoint.issue_token!.plaintext_token
    post "/webhooks/inbound/#{token}",
      params: JSON.generate(id: "evt_attempt_missing", type: "demo.received"),
      headers: { "CONTENT_TYPE" => "application/json" }
    event = @endpoint.inbound_events.find_by!(provider_event_id: "evt_attempt_missing")

    get "/admin/webhooks/endpoints/#{@endpoint.id}/events/#{SecureRandom.uuid}/action_attempts/#{event.action_attempts.first.id}"
    assert_response :not_found
  end

  test "endpoint and token rows reject identity changes and unsafe metadata" do
    assert_raises(ActiveRecord::ReadOnlyRecord) do
      @endpoint.update!(provider_name: "stripe")
    end
    assert_equal "demo", @endpoint.reload.provider_name

    assert_raises(ActiveRecord::RecordInvalid) do
      create_webhook_endpoint!(label: "Secret identity", provider_name: "demo", identity: { "api_key" => "hidden" })
    end

    issuance = @endpoint.issue_token!(actor: @user)
    token = issuance.endpoint_token
    assert_raises(ActiveRecord::ReadOnlyRecord) { token.update!(digest: "changed") }
    assert_raises(ActiveRecord::ReadOnlyRecord) { token.destroy! }

    assert_raises(ActiveRecord::RecordInvalid) do
      @endpoint.issue_token!(metadata: { "api_key" => "hidden" }, actor: @user)
    end
  end

  private

  def current_endpoint
    RecordingStudioWebhooks::Endpoint.current.find_by!(
      recording_studio_recording_id: @endpoint.recording_studio_recording_id
    )
  end

  def endpoint_params(overrides = {})
    {
      endpoint: {
        recording_studio_recording_id: @recording.id,
        label: "Rejected endpoint",
        provider_name: "demo",
        enabled: "1",
        identity_json: "{}",
        metadata_json: "{}",
        policy_json: "{}"
      }.merge(overrides)
    }
  end
end
