# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"
require "rack/mock"

class InboundSignatureTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @configuration = RecordingStudioWebhooks.configuration
    @original_authorizer = @configuration.admin_authorizer
    @original_scope = @configuration.admin_recording_scope
    @configuration.admin_authorizer = ->(context) { context.actor&.email == "admin@admin.com" }
    @configuration.admin_recording_scope = ->(_context) { RecordingStudio::Recording.where(trashed_at: nil) }

    register_provider_once("signature_gap")
    register_provider_once("signature_open", unsigned: true)
    register_provider_once(
      "signature_hmac",
      hmac: {
        signature_header: "X-Recording-Studio-Signature",
        timestamp_header: "X-Recording-Studio-Timestamp",
        tolerance: 300
      }
    )

    @user = User.find_or_create_by!(email: "admin@admin.com") do |user|
      user.password = "Password123!"
      user.password_confirmation = "Password123!"
    end
    workspace = Workspace.create!(name: "Signature #{SecureRandom.hex(4)}")
    @recording = RecordingStudio.create_root_recording!(workspace, actor: @user)
    result = RecordingStudioAccessible.bootstrap_owner_access!(recording: @recording, actor: @user)
    raise result.error if result.failure?

    Current.actor = @user
    @secret = "endpoint-signing-secret-#{SecureRandom.hex(8)}"
    @signed = create_endpoint("signature_hmac", "Signed endpoint", signing_secret: @secret)
    @open = create_endpoint("signature_open", "Unsigned endpoint")
    @gap = create_endpoint("signature_gap", "Unconfigured endpoint")
  end

  teardown do
    Current.actor = nil
    @configuration.admin_authorizer = @original_authorizer
    @configuration.admin_recording_scope = @original_scope
  end

  test "a provider with no signature check and no unsigned flag is rejected" do
    result = intake(@gap, token_source: "header")

    assert_equal 401, result.status
    assert_equal "signature_unconfigured", result.code
  end

  test "an unsigned provider accepts a header token and rejects a path token" do
    header = intake(@open, token_source: "header")
    path = intake(@open, token_source: "path", event_id: "evt_open_path")

    assert_equal "accepted", header.code
    assert_equal 401, path.status
    assert_equal "path_token_rejected", path.code

    post "/webhooks/inbound",
      params: body_for("evt_open_http"),
      headers: json_headers.merge("HTTP_AUTHORIZATION" => "Bearer #{token_for(@open)}")
    assert_response :accepted

    post "/webhooks/inbound/#{token_for(@open)}",
      params: body_for("evt_open_http_path"),
      headers: json_headers
    assert_response :unauthorized
  end

  test "a signed provider accepts a path token only with a fresh valid signature" do
    body = body_for("evt_signed_ok")
    accepted = intake(@signed, token_source: "path", body: body, headers: signature_headers(body))
    assert_equal "accepted", accepted.code

    rejected = intake(
      @signed,
      token_source: "path",
      body: body_for("evt_signed_bad"),
      headers: signature_headers(body_for("evt_signed_bad"), signature: "ab" * 32),
      event_id: "evt_signed_bad"
    )
    assert_equal 401, rejected.status
    assert_equal "signature_invalid", rejected.code

    stale_body = body_for("evt_signed_stale")
    stale = intake(
      @signed,
      token_source: "path",
      body: stale_body,
      headers: signature_headers(stale_body, timestamp: Time.now.to_i - 301),
      event_id: "evt_signed_stale"
    )
    assert_equal "signature_invalid", stale.code

    missing = intake(
      @signed,
      token_source: "path",
      body: body_for("evt_signed_missing"),
      headers: {},
      event_id: "evt_signed_missing"
    )
    assert_equal "signature_invalid", missing.code

    http_body = body_for("evt_signed_http")
    post "/webhooks/inbound/#{token_for(@signed)}",
      params: http_body,
      headers: json_headers.merge(signature_headers(http_body))
    assert_response :accepted
  end

  test "the signing secret is encrypted, shown once, and kept out of inspect and logs" do
    statements = []
    created = nil
    ActiveSupport::Notifications.subscribed(sql_subscriber(statements), "sql.active_record") do
      created = create_endpoint("signature_hmac", "Generated secret")
    end
    disclosure = created.signing_secret_disclosure
    secret = disclosure.plaintext_secret

    assert_raises(RecordingStudioWebhooks::Error) { disclosure.plaintext_secret }
    refute_includes disclosure.inspect, secret
    assert_equal secret, created.reload.signing_secret
    refute_includes created.inspect, secret
    refute_includes created.full_inspect, secret
    refute_includes statements.join, secret

    raw = created.class.connection.select_value(
      "SELECT signing_secret FROM recording_studio_webhooks_endpoints WHERE id = #{created.class.connection.quote(created.id)}"
    )
    refute_equal secret, raw
    refute_includes raw.to_s, secret

    renamed = RecordingStudioWebhooks::EndpointLifecycle.update!(
      endpoint: created,
      attributes: { label: "Renamed secret endpoint" },
      actor: @user
    )
    assert_equal secret, renamed.signing_secret
    assert_equal "Renamed secret endpoint", renamed.label
  end

  test "creating an hmac endpoint shows the signing secret once" do
    sign_in @user
    label = "Shown once #{SecureRandom.hex(4)}"

    post "/admin/webhooks/endpoints", params: {
      endpoint: {
        recording_studio_recording_id: @recording.id,
        label: label,
        provider_name: "signature_hmac",
        enabled: "1",
        identity_json: "{}",
        metadata_json: "{}",
        policy_json: "{}"
      }
    }

    assert_response :created
    assert_includes response.headers["Cache-Control"].to_s, "no-store"
    assert_includes response.body, "Copy this signing secret"
    secret = response.body[/\bname="signing_secret"[^>]*value="([^"]+)"/, 1] ||
      response.body[/value="([^"]+)"[^>]*name="signing_secret"/, 1]
    assert secret.present?
    endpoint = RecordingStudioWebhooks::Endpoint.current.find_by!(provider_name: "signature_hmac", label: label)
    assert_equal secret, endpoint.signing_secret

    get "/admin/screens/endpoints"
    assert_response :success
    refute_includes response.body, secret
  end

  test "request logs filter the path token and the signing secret parameter" do
    token = token_for(@signed)
    env = Rack::MockRequest.env_for("http://example.test/webhooks/inbound/#{token}?endpoint_token=#{token}")
    path = ActionDispatch::Request.new(env).filtered_path
    refute_includes path, token
    assert_includes path, "[FILTERED]"

    filtered = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters).filter(
      "endpoint_token" => token,
      "signing_secret" => @secret
    )
    assert_equal "[FILTERED]", filtered["endpoint_token"]
    assert_equal "[FILTERED]", filtered["signing_secret"]

    io = StringIO.new
    previous = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(io)
    body = body_for("evt_log_filter")
    post "/webhooks/inbound/#{token}", params: body, headers: json_headers.merge(signature_headers(body))
    refute_includes io.string, token
    refute_includes io.string, @secret
    assert_includes io.string, "[FILTERED]"
  ensure
    Rails.logger = previous if defined?(previous) && previous
  end

  private

  def register_provider_once(name, **)
    return if RecordingStudioWebhooks.configuration.providers.fetch(name)

    RecordingStudioWebhooks.register_provider(name, **)
  end

  def create_endpoint(provider_name, label, signing_secret: nil)
    attributes = {
      recording_studio_recording_id: @recording.id,
      label: label,
      provider_name: provider_name,
      identity: { "test" => true },
      metadata: {},
      policy_overrides: {},
      enabled: true
    }
    attributes[:signing_secret] = signing_secret if signing_secret
    RecordingStudioWebhooks::EndpointLifecycle.create!(
      endpoint: RecordingStudioWebhooks::Endpoint.new(attributes),
      actor: @user
    )
  end

  def token_for(endpoint)
    @tokens ||= {}
    @tokens[endpoint.id] ||= endpoint.issue_token!(actor: @user).plaintext_token
  end

  def body_for(event_id)
    JSON.generate(id: event_id, type: "demo.received")
  end

  def json_headers
    { "CONTENT_TYPE" => "application/json" }
  end

  def signature_headers(body, timestamp: Time.now.to_i, signature: nil)
    stamp = timestamp.to_s
    digest = signature || OpenSSL::HMAC.hexdigest("SHA256", @secret, "#{stamp}.#{body}")
    {
      "HTTP_X_RECORDING_STUDIO_TIMESTAMP" => stamp,
      "HTTP_X_RECORDING_STUDIO_SIGNATURE" => digest
    }
  end

  def intake(endpoint, token_source:, body: nil, headers: {}, event_id: "evt_default")
    payload = body || body_for(event_id)
    RecordingStudioWebhooks::InboundIntake.call(
      token: token_for(endpoint),
      token_source: token_source,
      raw_payload: payload,
      content_type: "application/json",
      headers: headers
    )
  end

  def sql_subscriber(statements)
    lambda do |_name, _start, _finish, _id, payload|
      statements << payload[:sql].to_s
    end
  end
end