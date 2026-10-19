# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class AdminMetricWidgetsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActiveSupport::Testing::TimeHelpers

  setup do
    @user = User.find_or_create_by!(email: "admin@admin.com") do |user|
      user.password = "Password123!"
      user.password_confirmation = "Password123!"
    end
    workspace = Workspace.create!(name: "Metric widgets #{SecureRandom.hex(4)}")
    @root = RecordingStudio.root_recording_for(workspace)
    result = RecordingStudioAccessible.bootstrap_owner_access!(
      recording: @root,
      actor: @user
    )
    raise result.error if result.failure?

    @admin_root = RecordingStudio.root_recording_for(AdminRoot.find_or_create_by!(name: "Admin"))
    grant!(@admin_root, @user, :admin)

    @endpoint = RecordingStudioWebhooks::EndpointLifecycle.create!(
      endpoint: RecordingStudioWebhooks::Endpoint.new(
        recording_studio_recording_id: @root.id,
        label: "Metric widget endpoint",
        provider_name: "demo",
        identity: {},
        metadata: {},
        policy_overrides: {}
      ),
      actor: @user
    )
    @token = @endpoint.issue_token!(actor: @user).endpoint_token
    seed_metric_rows!
  end

  test "admin hub renders metric cards from RecordingStudioMetrics" do
    sign_in @user
    get "/admin/sections/admin_webhooks"

    assert_response :success
    assert_includes response.body, "Stuck retries"
    assert_includes response.body, "Failed attempts"
    assert_includes response.body, "Event status"
    assert_includes response.body, "/admin/screens/action_attempts"
    assert_includes response.body, "status=failed"
    assert_includes response.body, "/admin/screens/webhook_traffic"

    stuck = RecordingStudioWebhooks::Admin::MetricWidgets.ensure_stuck_widget!
    failed = RecordingStudioWebhooks::Admin::MetricWidgets.ensure_failed_widget!
    status = RecordingStudioWebhooks::Admin::MetricWidgets.ensure_event_status_widget!
    context = admin_context

    stuck_resolved = stuck.resolve(context)
    assert_equal 1, stuck_resolved.value
    assert_match(/Oldest wait is \d+ seconds past due/, stuck_resolved.info)

    failed_resolved = failed.resolve(context)
    assert_operator failed_resolved.value.to_i, :>=, 1
    refute_empty failed_resolved.series

    status_resolved = status.resolve(context)
    texts = status_resolved.items.map { |item| item[:text] || item["text"] }
    assert_includes texts, "accepted"
  end

  private

  def seed_metric_rows!
    travel_to Time.current do
      failed_event = create_event!("invoice.failed")
      failed_event.action_attempts.create!(
        action_name: "demo.record",
        execution_position: 0,
        status: "failed",
        attempts: 1,
        completed_at: Time.current,
        last_error: "action_execution_failed",
        endpoint_snapshot: failed_event.endpoint_snapshot,
        token_snapshot: failed_event.token_snapshot,
        policy_snapshot: failed_event.policy_snapshot,
        action_snapshot: { "name" => "demo.record" },
        attempt_history: []
      )

      stuck_event = create_event!("invoice.retry")
      stuck = stuck_event.action_attempts.create!(
        action_name: "demo.record",
        execution_position: 0,
        status: "retrying",
        attempts: 1,
        completed_at: nil,
        last_error: nil,
        endpoint_snapshot: stuck_event.endpoint_snapshot,
        token_snapshot: stuck_event.token_snapshot,
        policy_snapshot: stuck_event.policy_snapshot,
        action_snapshot: { "name" => "demo.record" },
        attempt_history: []
      )
      stuck.update_columns(
        next_attempt_at: Time.current - RecordingStudioWebhooks::Metrics::STUCK_RETRY_GRACE - 30.seconds
      )
    end
  end

  def create_event!(event_type)
    RecordingStudioWebhooks::InboundEvent.create!(
      endpoint: @endpoint,
      endpoint_token: @token,
      provider_name: @endpoint.provider_name,
      event_type: event_type,
      provider_event_id: "evt_#{SecureRandom.hex(6)}",
      payload_digest: SecureRandom.hex(16),
      deduplication_key: "event:#{SecureRandom.uuid}",
      payload: { "type" => event_type },
      provenance: { "request_id" => SecureRandom.uuid },
      endpoint_snapshot: @endpoint.snapshot,
      token_snapshot: @token.snapshot,
      policy_snapshot: { "values" => RecordingStudioWebhooks::Policy.default.to_h },
      received_at: Time.current,
      status: "accepted"
    )
  end

  def admin_context
    actor = @user
    root = @root
    Struct.new(:current_actor, :root_recording, :timezone, :blast_radius) do
      def admin_screen_path(key)
        "/admin/screens/#{key}"
      end
    end.new(actor, root, "UTC", :site)
  end

  def grant!(recording, actor, role)
    return if RecordingStudioAccessible.authorized?(actor: actor, recording: recording, role: role)

    original = RecordingStudioAccessible.configuration.access_management_authorizer
    RecordingStudioAccessible.configuration.access_management_authorizer = ->(**) { true }
    result = RecordingStudioAccessible.grant_access(
      recording: recording,
      actor: actor,
      role: role,
      manager_actor: actor
    )
    raise result.error if result.failure?
  ensure
    RecordingStudioAccessible.configuration.access_management_authorizer = original
  end
end
