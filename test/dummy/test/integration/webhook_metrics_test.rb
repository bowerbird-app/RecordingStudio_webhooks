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

  test "api_authorize allows AdminRoot staff and denies non-admins" do
    authorize = RecordingStudioMetrics.registry.api_authorize_for(:webhook_events)
    assert_equal RecordingStudioWebhooks::Metrics::AUTHORIZE, authorize

    assert authorize.call(GrantContext.new(Grant.new(@staff)))
    refute authorize.call(GrantContext.new(Grant.new(@outsider)))
    refute authorize.call(GrantContext.new(Grant.new(nil)))
  end

  private

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
