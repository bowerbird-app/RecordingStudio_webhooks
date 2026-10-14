# frozen_string_literal: true

require "test_helper"

class WebhookMetricsTest < ActiveSupport::TestCase
  GrantContext = Struct.new(:access_grant)
  Grant = Struct.new(:actor)

  setup do
    @staff = User.create!(
      email: "metrics-staff-#{SecureRandom.hex(4)}@example.com",
      password: "Password",
      password_confirmation: "Password"
    )
    @outsider = User.create!(
      email: "metrics-outsider-#{SecureRandom.hex(4)}@example.com",
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
    Current.actor = nil
  end

  teardown do
    Current.actor = nil
  end

  test "registered webhook metrics return seeded event, attempt, and endpoint values" do
    identifiers = RecordingStudioMetrics.definitions.map(&:identifier)
    %w[
      webhook_events.over_time
      webhook_events.by_provider
      webhook_attempts.by_status
      webhook_endpoints.enabled
    ].each { |identifier| assert_includes identifiers, identifier }

    opened = timeseries_counts(
      execute(
        "webhook_events.over_time",
        interval: "day",
        start_at: Time.utc(2026, 10, 6),
        end_at: Time.utc(2026, 10, 10)
      )
    )
    assert_equal events_received_between(Time.utc(2026, 10, 7), Time.utc(2026, 10, 8)), opened["2026-10-07"]
    assert_equal events_received_between(Time.utc(2026, 10, 8), Time.utc(2026, 10, 9)), opened["2026-10-08"]
    assert_operator opened["2026-10-07"], :>=, 1
    assert_operator opened["2026-10-08"], :>=, 2

    provider_counts = breakdown_counts(execute("webhook_events.by_provider"))
    RecordingStudioWebhooks::InboundEvent.distinct.pluck(:provider_name).each do |provider|
      assert_equal RecordingStudioWebhooks::InboundEvent.where(provider_name: provider).count,
                   provider_counts[provider].to_i
    end

    status_counts = breakdown_counts(execute("webhook_attempts.by_status"))
    RecordingStudioWebhooks::ActionAttempt::STATUSES.each do |status|
      assert_equal RecordingStudioWebhooks::ActionAttempt.where(status: status).count, status_counts[status].to_i
    end

    enabled = RecordingStudioWebhooks::Endpoint.current.where(enabled: true).count
    assert_equal enabled, execute("webhook_endpoints.enabled").value
    assert_operator RecordingStudioWebhooks::Endpoint.current.where(enabled: false).count, :>=, 1
  end

  test "stuck retries count pending retries overdue by at least the grace period" do
    freeze_time do
      seed_stuck_retries!

      assert_equal 300, RecordingStudioWebhooks::Metrics::STUCK_RETRY_GRACE.to_i
      result = execute("webhook_attempts.stuck")
      assert_equal "count", result.unit
      assert_equal 9, result.value
      assert_equal expected_stuck.count, result.value

      assert_equal 8, execute("webhook_attempts.stuck", filters: { provider: "billing" }).value
      assert_equal 1, execute("webhook_attempts.stuck", filters: { endpoint: @demo.label }).value
      assert_equal 1, execute("webhook_attempts.stuck", filters: { action_name: "demo.record" }).value
      assert_equal 9, execute("webhook_attempts.stuck", filters: { action_name: "all" }).value
      event_id = expected_stuck.where(action_name: "demo.record").pick(:inbound_event_id)
      assert_equal 1, execute("webhook_attempts.stuck", filters: { event_id: event_id }).value
    end
  end

  test "stuck retries group by action name and fold small groups into other" do
    freeze_time do
      seed_stuck_retries!

      result = execute("webhook_attempts.stuck", group_by: "action_name")
      assert_equal 9, result.value
      assert_equal [{ key: "billing.record", value: 8 }], result.groups
      assert_equal({ groups: 1, value: 1 }, result.other)

      assert_raises(RecordingStudioMetrics::Errors::InvalidGroupBy) do
        execute("webhook_attempts.stuck", group_by: "status")
      end
    end
  end

  test "oldest stuck age is seconds since the earliest overdue retry" do
    freeze_time do
      assert_nil execute("webhook_attempts.oldest_stuck_age").value

      seed_stuck_retries!
      result = execute("webhook_attempts.oldest_stuck_age")
      assert_equal "seconds", result.unit
      assert_equal 6.hours.to_i, result.value
      assert_equal 10.minutes.to_i,
                   execute("webhook_attempts.oldest_stuck_age", filters: { provider: "demo" }).value
    end
  end

  test "stuck metric catalog entries carry units, group_by, and operations exposure" do
    stuck = RecordingStudioMetrics.find("webhook_attempts.stuck").catalog_metadata
    assert_equal "count", stuck[:unit]
    assert_equal [:action_name], stuck[:group_by]
    assert_equal 5, stuck[:min_group_size]
    assert_equal [:operations], stuck[:exposed_apis]
    assert_equal :site, stuck[:blast_radius]
    assert_equal %i[provider endpoint action_name event_id], stuck[:filters].map { |filter| filter[:name] }
    assert stuck[:description].present?

    age = RecordingStudioMetrics.find("webhook_attempts.oldest_stuck_age").catalog_metadata
    assert_equal "seconds", age[:unit]
    assert_equal [], age[:group_by]
    assert_equal %i[provider endpoint action_name event_id], age[:filters].map { |filter| filter[:name] }
  end

  test "api_authorize allows AdminRoot staff and denies non-admins" do
    authorize = RecordingStudioMetrics.registry.api_authorize_for(:webhook_events)
    assert_equal RecordingStudioWebhooks::Metrics::AUTHORIZE, authorize

    assert authorize.call(GrantContext.new(Grant.new(@staff)))
    refute authorize.call(GrantContext.new(Grant.new(@outsider)))
    refute authorize.call(GrantContext.new(Grant.new(nil)))
  end

  private

  def seed_stuck_retries!
    stuck_at = Time.current - RecordingStudioWebhooks::Metrics::STUCK_RETRY_GRACE
    create_retry!(@demo, @demo_token, "demo.record", "retrying", Time.current - 10.minutes)
    6.times do |index|
      create_retry!(@billing, @billing_token, "billing.record", "retrying", Time.current - (1 + index).hours)
    end
    create_retry!(@billing, @billing_token, "billing.record", "retrying", Time.current - 2.hours)
      .update_columns(status: "pending")
    # Due at exactly now - grace is stuck (ActionAttempt.due uses <=).
    create_retry!(@billing, @billing_token, "billing.record", "retrying", stuck_at)
    # Not stuck: inside the grace period, 1s short of it, future, unscheduled, terminal, running.
    create_retry!(@billing, @billing_token, "billing.record", "retrying", Time.current - 1.minute)
    create_retry!(@billing, @billing_token, "billing.record", "retrying", stuck_at + 1.second)
    create_retry!(@billing, @billing_token, "billing.record", "retrying", Time.current + 1.minute)
    create_retry!(@billing, @billing_token, "billing.record", "pending", nil)
    create_retry!(@billing, @billing_token, "billing.record", "failed", Time.current - 1.day)
    create_retry!(@billing, @billing_token, "billing.record", "running", Time.current - 1.day)
  end

  def create_retry!(endpoint, token, action_name, status, next_attempt_at)
    attempt = create_attempt!(create_event!(endpoint, token, "invoice.retry"), action_name, status)
    attempt.update_columns(next_attempt_at: next_attempt_at)
    attempt
  end

  # Mirrors the documented definition independently of the metric code.
  def expected_stuck
    RecordingStudioWebhooks::ActionAttempt
      .where(status: %w[pending retrying])
      .where(next_attempt_at: ..(Time.current - 300.seconds))
  end

  def execute(identifier, **params)
    RecordingStudioMetrics.execute(
      identifier,
      context: site_context,
      cache: false,
      **params
    )
  end

  def site_context
    RecordingStudioMetrics::Context.new(
      scope: :site,
      actor: @staff,
      site_authorized: true,
      timezone: "UTC"
    )
  end

  def seed_webhooks!
    demo = create_endpoint!("demo", "Metrics demo #{SecureRandom.hex(4)}", enabled: true)
    other = create_endpoint!("billing", "Metrics billing #{SecureRandom.hex(4)}", enabled: true)
    create_endpoint!("demo", "Metrics disabled #{SecureRandom.hex(4)}", enabled: false)

    demo_token = demo.issue_token!(actor: @staff).endpoint_token
    other_token = other.issue_token!(actor: @staff).endpoint_token
    @demo = demo
    @billing = other
    @demo_token = demo_token
    @billing_token = other_token

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

  def breakdown_counts(result)
    result.data.to_h { |row| [row[:key].to_s, row[:value] || row["value"]] }
  end

  def timeseries_counts(result)
    result.data.to_h { |row| [(row[:date] || row["date"]).to_s, row[:value] || row["value"]] }
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
