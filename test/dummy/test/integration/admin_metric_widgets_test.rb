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
    assert_equal :chart, stuck_resolved.type
    assert_equal 5, stuck_resolved.value
    assert_match(/Oldest wait is \d+ seconds past due/, stuck_resolved.info)
    refute_empty stuck_resolved.series
    assert_includes stuck_series_labels(stuck_resolved), "demo.record"

    failed_resolved = failed.resolve(context)
    assert_operator failed_resolved.value.to_i, :>=, 1
    refute_empty failed_resolved.series

    status_resolved = status.resolve(context)
    texts = status_resolved.items.map { |item| item[:text] || item["text"] }
    assert_includes texts, "accepted"
  end

  test "action attempts screen is enabled from the Admin Webhooks section links" do
    RecordingStudioWebhooks::Admin::Registration.register!

    assert_includes RecordingStudioWebhooks::AdminWebhooksSection.links.map(&:name), :action_attempts
    assert RecordingStudioAdmin.screen_enabled?(
      key: "action_attempts",
      recording: @admin_root,
      context: admin_path_context
    )

    sign_in @user
    get "/admin/screens/action_attempts"

    assert_response :success
    assert_includes response.body, "Action attempts"
  end

  test "every screen linked from admin webhooks widgets returns 200 when the section is enabled" do
    RecordingStudioWebhooks::Admin::Registration.register!
    context = admin_path_context
    linked_keys = widget_linked_screen_keys(admin_context)

    assert_includes linked_keys, "providers"
    assert_includes linked_keys, "actions"
    assert_includes linked_keys, "endpoints"
    refute_empty linked_keys

    sign_in @user
    linked_keys.each do |key|
      assert_includes RecordingStudioWebhooks::AdminWebhooksSection.links.map(&:name), key.to_sym
      assert RecordingStudioAdmin.screen_enabled?(
        key: key,
        recording: @admin_root,
        context: context
      ), "#{key} should be enabled on the Admin root"

      get "/admin/screens/#{key}"
      assert_response :success, "#{key} expected 200, got #{response.status}"
    end
  end

  test "action attempts widget matches the action attempts screen on completed_at last 4 weeks" do
    seed_action_attempt_count_mismatch_rows!
    context = admin_context
    range = RecordingStudioWebhooks::AdminWebhooksTrafficDefinition.last_4_weeks_range(Time.current)
    screen_count = RecordingStudioWebhooks::AdminWebhooksTrafficDefinition
                   .action_attempt_relation(context)
                   .where(completed_at: range)
                   .count
    widget_count = RecordingStudioWebhooks::AdminWebhooksTrafficDefinition
                   .ensure_action_attempts_widget_definition!
                   .resolve(context)
                   .value

    assert_equal 3, screen_count
    assert_equal screen_count, widget_count
  end

  test "action attempts chart follows the status filter" do
    seed_action_attempt_status_chart_rows!
    sign_in @user
    period = RecordingStudioAdmin::Period.from_preset_key(:last_4_weeks)
    chart_params = {
      date_range_preset: "last_4_weeks",
      start_date: period.start_date.iso8601,
      end_date: period.end_date.iso8601,
      group_by: "week"
    }

    get "/admin/screens/action_attempts/chart", params: chart_params
    assert_response :success
    assert_equal 6, chart_series_total(response.body)

    get "/admin/screens/action_attempts/chart", params: chart_params.merge(status: "failed")
    assert_response :success
    assert_equal 3, chart_series_total(response.body)

    get "/admin/screens/action_attempts/table", params: chart_params.merge(status: "failed")
    assert_response :success
    assert_includes response.body, "demo.failed_for_chart"
    refute_includes response.body, "demo.succeeded_for_chart"
  end

  test "failed attempts widget matches the action attempts screen on root and completed_at" do
    seed_failed_count_mismatch_rows!
    context = admin_context
    range = RecordingStudioWebhooks::AdminWebhooksTrafficDefinition.last_4_weeks_range(Time.current)
    screen_count = RecordingStudioWebhooks::AdminWebhooksTrafficDefinition
                   .action_attempt_relation(context)
                   .where(status: "failed", completed_at: range)
                   .count
    widget_count = RecordingStudioWebhooks::Admin::MetricWidgets.ensure_failed_widget!.resolve(context).value

    assert_equal 3, screen_count
    assert_equal screen_count, widget_count

    sign_in @user
    period = RecordingStudioAdmin::Period.from_preset_key(:last_4_weeks)
    get "/admin/screens/action_attempts/table", params: {
      status: "failed",
      date_range_preset: "last_4_weeks",
      start_date: period.start_date.iso8601,
      end_date: period.end_date.iso8601
    }

    assert_response :success
    names = response.body.scan(/demo\.(?:record|created_outside|edge_week|finished_outside|other_root)/).uniq
    assert_equal %w[demo.record demo.created_outside demo.edge_week].sort, names.sort
    refute_includes response.body, "demo.finished_outside"
    refute_includes response.body, "demo.other_root"
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

      5.times do
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
  end

  def seed_action_attempt_count_mismatch_rows!
    create_failed_attempt!("invoice.window", created_at: Time.current, completed_at: Time.current, action_name: "demo.window")
    create_failed_attempt!("invoice.created_outside", created_at: 40.days.ago, completed_at: Time.current, action_name: "demo.created_outside")
    create_failed_attempt!("invoice.finished_outside", created_at: Time.current, completed_at: 40.days.ago, action_name: "demo.finished_outside")
    event = create_event!("invoice.retrying")
    event.action_attempts.create!(
      action_name: "demo.retrying",
      execution_position: 0,
      status: "retrying",
      attempts: 1,
      completed_at: nil,
      last_error: nil,
      endpoint_snapshot: event.endpoint_snapshot,
      token_snapshot: event.token_snapshot,
      policy_snapshot: event.policy_snapshot,
      action_snapshot: { "name" => "demo.retrying" },
      attempt_history: []
    )
  end

  def seed_action_attempt_status_chart_rows!
    3.times do |index|
      create_attempt_with_status!(
        "invoice.succeeded_#{index}",
        status: "succeeded",
        action_name: "demo.succeeded_for_chart"
      )
    end
    2.times do |index|
      create_attempt_with_status!(
        "invoice.failed_#{index}",
        status: "failed",
        action_name: "demo.failed_for_chart"
      )
    end
  end

  def create_attempt_with_status!(event_type, status:, action_name:)
    event = create_event!(event_type)
    event.action_attempts.create!(
      action_name: action_name,
      execution_position: 0,
      status: status,
      attempts: 1,
      completed_at: Time.current,
      last_error: (status == "failed" ? "action_execution_failed" : nil),
      endpoint_snapshot: event.endpoint_snapshot,
      token_snapshot: event.token_snapshot,
      policy_snapshot: event.policy_snapshot,
      action_snapshot: { "name" => action_name },
      attempt_history: []
    )
  end

  def chart_series_total(body)
    match = body.match(/data-flat-pack--chart-series-value="([^"]+)"/)
    assert match, "expected a Flatpack chart series in the response"
    series = JSON.parse(CGI.unescapeHTML(match[1]))
    Array(series).sum do |entry|
      Array(entry["data"] || entry[:data]).sum { |point| (point["y"] || point[:y]).to_i }
    end
  end

  def seed_failed_count_mismatch_rows!
    edge = RecordingStudioAdmin::Period.from_preset_key(:last_4_weeks).start_date.beginning_of_day
    create_failed_attempt!("invoice.created_outside", created_at: 40.days.ago, completed_at: Time.current, action_name: "demo.created_outside")
    create_failed_attempt!("invoice.finished_outside", created_at: Time.current, completed_at: 40.days.ago, action_name: "demo.finished_outside")
    create_failed_attempt!("invoice.edge_week", created_at: Time.current, completed_at: edge, action_name: "demo.edge_week")

    other_workspace = Workspace.create!(name: "Other metric root #{SecureRandom.hex(4)}")
    other_root = RecordingStudio.root_recording_for(other_workspace)
    other_endpoint = RecordingStudioWebhooks::EndpointLifecycle.create!(
      endpoint: RecordingStudioWebhooks::Endpoint.new(
        recording_studio_recording_id: other_root.id,
        label: "Other metric endpoint",
        provider_name: "demo",
        identity: {},
        metadata: {},
        policy_overrides: {}
      ),
      actor: @user
    )
    other_token = other_endpoint.issue_token!(actor: @user).endpoint_token
    create_failed_attempt!(
      "invoice.other_root",
      created_at: Time.current,
      completed_at: Time.current,
      endpoint: other_endpoint,
      token: other_token,
      action_name: "demo.other_root"
    )
  end

  def create_failed_attempt!(event_type, created_at:, completed_at:, endpoint: @endpoint, token: @token, action_name: "demo.record")
    event = create_event!(event_type, endpoint: endpoint, token: token)
    attempt = event.action_attempts.create!(
      action_name: action_name,
      execution_position: 0,
      status: "failed",
      attempts: 1,
      completed_at: completed_at,
      last_error: "action_execution_failed",
      endpoint_snapshot: event.endpoint_snapshot,
      token_snapshot: event.token_snapshot,
      policy_snapshot: event.policy_snapshot,
      action_snapshot: { "name" => action_name },
      attempt_history: []
    )
    attempt.update_columns(created_at: created_at, completed_at: completed_at)
    attempt
  end

  def create_event!(event_type, endpoint: @endpoint, token: @token)
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

  def admin_path_context
    Object.new.tap do |context|
      def context.admin_screen_path(key)
        "/admin/screens/#{key}"
      end
    end
  end

  def widget_linked_screen_keys(context)
    RecordingStudioWebhooks::AdminWebhooksSection.widget_usages.filter_map do |usage|
      widget = RecordingStudioAdmin.widget_for(usage.key)
      next unless widget

      href = widget.resolve(context).link_to.to_s
      match = href.match(%r{/admin/screens/([^/?#]+)})
      match&.captures&.first
    end.uniq
  end

  def stuck_series_labels(resolved)
    Array(resolved.series).flat_map do |series|
      Array(series[:data] || series["data"]).map { |point| point[:x] || point["x"] }
    end
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
