# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"
require_relative "../support/webhook_admin_examples"

class AdminScreenBranchesTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActiveSupport::Testing::TimeHelpers
  include WebhookAdminExamples

  setup do
    setup_webhook_admin!
    sign_in @user
  end

  teardown { teardown_webhook_admin! }

  test "admin screens apply search, charts, badges, and long labels" do
    long_label = "Billing production endpoint #{SecureRandom.hex(8)}"
    long_endpoint = create_webhook_endpoint!(label: long_label, provider_name: "demo")
    token = long_endpoint.issue_token!(actor: @user).plaintext_token
    post "/webhooks/inbound/#{token}",
      params: JSON.generate(id: "evt_screen", type: "demo.received"),
      headers: { "CONTENT_TYPE" => "application/json" }
    assert_response :accepted
    event = long_endpoint.inbound_events.find_by!(provider_event_id: "evt_screen")
    attempt = event.action_attempts.first
    assert_equal "action_succeeded", RecordingStudioWebhooks::ExecuteActionAttempt.call(attempt.id).code
    running_token = long_endpoint.issue_token!.plaintext_token
    post "/webhooks/inbound/#{running_token}",
      params: JSON.generate(id: "evt_screen_running", type: "demo.received"),
      headers: { "CONTENT_TYPE" => "application/json" }
    assert_response :accepted
    running = long_endpoint.inbound_events.find_by!(provider_event_id: "evt_screen_running").action_attempts.first
    running.queue_for_dispatch!
    running.claim_execution!
    long_endpoint.issue_token!(expires_at: 1.minute.from_now, actor: @user)

    get "/admin/screens/endpoints/table", params: { search: "Billing", status: "enabled" }
    assert_response :success
    assert_includes response.body, long_label.truncate(40)
    assert_includes response.body, long_label

    get "/admin/screens/providers/table", params: { search: "dem" }
    assert_response :success
    assert_includes response.body, "demo"

    get "/admin/screens/actions/table", params: { search: "received" }
    assert_response :success
    assert_includes response.body, "demo.received"

    get "/admin/screens/webhook_traffic/chart", params: { group_by: "hour", endpoint: long_label }
    assert_response :success
    get "/admin/screens/webhook_traffic/chart", params: { group_by: "month", endpoint: long_label }
    assert_response :success

    get "/admin/screens/action_attempts/chart", params: { group_by: "hour", status: "succeeded" }
    assert_response :success
    get "/admin/screens/action_attempts/chart", params: { group_by: "month" }
    assert_response :success
    get "/admin/screens/action_attempts/table", params: { event_id: event.id, status: "succeeded" }
    assert_response :success
    assert_includes response.body, "demo.received"

    attempt_row = event.action_attempts.first
    attempt_row.queue_for_dispatch!
    attempt_row.claim_execution! if attempt_row.reload.pending? || attempt_row.queued?
    get "/admin/screens/action_attempts/table", params: { status: "running" }
    assert_response :success

    get "/admin/sections/admin_webhooks"
    assert_response :success
    assert_includes response.body, "demo.received"

    travel 5.minutes do
      get "/admin/screens/tokens/table"
      assert_response :success
      assert_includes response.body, "Expired"
    end
  end

  test "traffic helpers report week ranges and percent change" do
    reference = Time.zone.parse("2026-03-18 15:00:00")
    definition = RecordingStudioWebhooks::AdminWebhooksTrafficDefinition

    week = definition.weekly_range(reference)
    previous = definition.previous_weekly_range(reference)
    assert_operator week.begin, :<=, reference
    assert_operator week.end, :>=, reference
    assert_operator previous.end, :<, week.begin

    assert_equal :success, definition.enabled_status_badge_style(true)
    assert_equal :default, definition.enabled_status_badge_style(false)
    assert_equal "0%", definition.percent_change_label(current_count: 0, previous_count: 0)
    assert_equal "+100%", definition.percent_change_label(current_count: 2, previous_count: 0)
    assert_equal "-50%", definition.percent_change_label(current_count: 1, previous_count: 2)
  end
end
