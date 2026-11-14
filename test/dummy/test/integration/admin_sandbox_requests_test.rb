# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"
require_relative "../support/webhook_admin_examples"

class AdminSandboxRequestsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include WebhookAdminExamples

  setup do
    setup_webhook_admin!
    sign_in @user
    register_probe_providers!
  end

  teardown { teardown_webhook_admin! }

  test "sandbox show renders the dry-run form for an endpoint and stores nothing" do
    get "/admin/webhooks/endpoints/#{@endpoint.id}/sandbox"

    assert_response :success
    assert_includes response.body, "Webhook Sandbox"
    assert_includes response.body, @endpoint.label
    assert_equal 0, @endpoint.inbound_events.count
  end

  test "a valid dry run redacts secrets, checks the timestamp, and does not persist" do
    secret = "never-render-#{SecureRandom.hex(4)}"

    post_sandbox(
      endpoint_id: @endpoint.id,
      provider_name: "demo",
      event_type: "demo.received",
      headers_json: JSON.generate("x-webhook-timestamp" => Time.current.to_i.to_s),
      payload: JSON.generate(type: "demo.received", token: secret, id: "sample")
    )

    assert_response :success
    assert_includes response.body, "demo.received"
    assert_includes response.body, "[FILTERED]"
    assert_includes response.body, "within five minutes"
    assert_includes response.body, "No signature verifier configured."
    assert_includes response.body, "custom"
    redacted = response.body[/<code[^>]*language-json">(.*?)<\/code>/m, 1].to_s
    assert_includes redacted, "[FILTERED]"
    refute_includes redacted, secret
    assert_equal 0, @endpoint.inbound_events.count
  end

  test "sandbox rejects invalid payloads, headers, event names, and oversized bodies" do
    post_sandbox(provider_name: "demo", event_type: "demo.received", payload: "{")
    assert_response :unprocessable_entity
    assert_includes response.body, "Provide a JSON payload and a valid event type."

    post_sandbox(
      provider_name: "demo",
      event_type: "demo.received",
      headers_json: "[]",
      payload: JSON.generate(type: "demo.received")
    )
    assert_response :unprocessable_entity

    post_sandbox(
      provider_name: "demo",
      event_type: "Not A Name",
      payload: JSON.generate(type: "demo.received")
    )
    assert_response :unprocessable_entity

    post_sandbox(event_type: "demo.received", payload: JSON.generate(type: "demo.received"))
    assert_response :unprocessable_entity

    @webhooks_configuration.max_payload_bytes = 32
    post_sandbox(
      provider_name: "demo",
      event_type: "demo.received",
      payload: JSON.generate(type: "demo.received", note: "x" * 80)
    )
    assert_response :unprocessable_entity
    assert_equal 0, @endpoint.inbound_events.count
  end

  test "sandbox reports timestamp drift, unparseable timestamps, and a symbol dispatcher" do
    post_sandbox(sandbox_fields("x-webhook-timestamp" => 2.hours.ago.iso8601))
    assert_response :success
    assert_includes response.body, "Timestamp drift exceeds five minutes."

    post_sandbox(sandbox_fields("x-webhook-timestamp" => "not-a-timestamp"))
    assert_response :success
    assert_includes response.body, "Timestamp could not be parsed."

    post_sandbox(sandbox_fields)
    assert_response :success
    assert_includes response.body, "No timestamp header provided."

    @webhooks_configuration.dispatcher = :active_job
    post_sandbox(sandbox_fields("x-webhook-timestamp" => Time.current.iso8601))
    assert_response :success
    assert_includes response.body, "active_job"
  end

  test "sandbox reports signature verifier accept, reject, and raise outcomes" do
    post_sandbox(sandbox_fields.merge(provider_name: "stripe", event_type: "invoice.paid"))
    assert_response :success
    assert_includes response.body, "Signature verifier accepted payload."

    post_sandbox(sandbox_fields.merge(provider_name: "probe_reject"))
    assert_response :success
    assert_includes response.body, "Signature verifier rejected payload."
    assert_includes response.body, "not verified"

    post_sandbox(sandbox_fields.merge(provider_name: "probe_raise"))
    assert_response :success
    assert_includes response.body, "Signature verifier raised an error."

    post_sandbox(sandbox_fields.merge(provider_name: "probe_keywords"))
    assert_response :success
    assert_includes response.body, "Signature verifier accepted payload."

    post_sandbox(sandbox_fields.merge(provider_name: "probe_zero"))
    assert_response :success
    assert_includes response.body, "Signature verifier accepted payload."

    post_sandbox(sandbox_fields.merge(provider_name: "probe_rest"))
    assert_response :success
    assert_includes response.body, "Signature verifier accepted payload."
  end

  test "sandbox extracts the event type when the form leaves it blank" do
    post_sandbox(
      provider_name: "probe_extract_kw",
      headers_json: "{}",
      payload: JSON.generate(type: "demo.received")
    )
    assert_response :success
    assert_includes response.body, "demo.received"

    post_sandbox(
      provider_name: "probe_extract_zero",
      payload: JSON.generate(type: "ignored")
    )
    assert_response :success
    assert_includes response.body, "demo.received"

    post_sandbox(
      provider_name: "probe_extract_pos",
      payload: JSON.generate(type: "invoice.paid")
    )
    assert_response :success
    assert_includes response.body, "invoice.paid"

    post_sandbox(
      provider_name: "probe_plain",
      endpoint_id: SecureRandom.uuid,
      payload: JSON.generate(type: "demo.received")
    )
    assert_response :success
    assert_match(/Endpoint resolved.{0,300}\bno\b/m, response.body)
    assert_includes response.body, "demo.received"
  end

  private

  def sandbox_fields(headers = {})
    {
      endpoint_id: @endpoint.id,
      provider_name: "demo",
      event_type: "demo.received",
      headers_json: JSON.generate(headers),
      payload: JSON.generate(type: "demo.received", id: "sample")
    }
  end

  def register_probe_providers!
    register_provider_once("probe_reject", signature_verifier: ->(_payload) { false })
    register_provider_once("probe_raise", signature_verifier: ->(_payload) { raise "verifier failed" })
    register_provider_once("probe_keywords", signature_verifier: ->(payload:, headers:) { payload.is_a?(Hash) && headers.is_a?(Hash) })
    register_provider_once("probe_zero", signature_verifier: -> { true })
    register_provider_once("probe_rest", signature_verifier: ->(**kwargs) { kwargs.key?(:payload) })
    register_provider_once("probe_extract_kw", event_type_extractor: ->(payload:) { payload["type"] })
    register_provider_once("probe_extract_zero", event_type_extractor: -> { "demo.received" })
    register_provider_once("probe_extract_pos", event_type_extractor: ->(payload) { payload.fetch("type") })
    register_provider_once("probe_plain")
  end
end
