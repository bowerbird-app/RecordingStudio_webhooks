# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class AdminRootReadScopeTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActiveSupport::Testing::TimeHelpers

  FILTER_SCREENS = %w[webhook_traffic providers endpoints action_attempts tokens].freeze

  setup do
    @owner = create_user!("owner")
    @viewer = create_user!("viewer")
    @foreign_owner = create_user!("foreign-owner")
    Current.actor = @owner

    @own_root = create_root!("Studio Workspace", @owner)
    grant_view!(@own_root, @viewer, manager: @owner)

    @foreign_root = create_root!("Foreign Workspace", @foreign_owner)

    @retired_endpoint = create_endpoint!(@own_root, @owner, label: "Retired local endpoint", provider_name: "localprov")
    retired_token = @retired_endpoint.issue_token!(actor: @owner).endpoint_token
    @retired_attempt = create_attempt!(
      @retired_endpoint,
      retired_token,
      action_name: "localprov.retired",
      payload_marker: "retired-payload-marker",
      history_marker: "retired-history-marker"
    )

    @own_endpoint = RecordingStudioWebhooks::EndpointLifecycle.update!(
      endpoint: @retired_endpoint,
      attributes: { label: "Current local endpoint" },
      actor: @owner
    )
    own_token = @own_endpoint.issue_token!(actor: @owner).endpoint_token
    @own_attempt = create_attempt!(
      @own_endpoint,
      own_token,
      action_name: "localprov.kept",
      payload_marker: "own-payload-marker",
      history_marker: "own-history-marker"
    )

    Current.actor = @foreign_owner
    @foreign_endpoint = create_endpoint!(
      @foreign_root,
      @foreign_owner,
      label: "Foreign root endpoint",
      provider_name: "foreignprov"
    )
    foreign_token = @foreign_endpoint.issue_token!(actor: @foreign_owner).endpoint_token
    @foreign_attempt = create_attempt!(
      @foreign_endpoint,
      foreign_token,
      action_name: "foreignprov.secret",
      payload_marker: "foreign-payload-marker",
      history_marker: "foreign-history-marker"
    )
    Current.actor = @viewer

    RecordingStudioWebhooks::Admin::Registration.register!
  end

  teardown do
    Current.actor = nil
  end

  test "another root's attempt is not found and the current root's attempt renders" do
    sign_in @viewer

    get "/admin/webhooks/action_attempts/#{@foreign_attempt.id}"
    assert_response :not_found
    refute_includes response.body, "foreign-payload-marker"
    refute_includes response.body, "foreign-history-marker"

    get "/admin/webhooks/attempts/#{@foreign_attempt.id}"
    assert_response :not_found
    refute_includes response.body, "foreignprov.secret"

    get nested_attempt_path(@foreign_endpoint, @foreign_attempt)
    assert_response :not_found

    get nested_attempt_path(@own_endpoint, @foreign_attempt)
    assert_response :not_found

    get "/admin/webhooks/action_attempts/#{@own_attempt.id}"
    assert_response :success
    assert_includes response.body, "localprov.kept"
    assert_includes response.body, "own-payload-marker"
    assert_includes response.body, "own-history-marker"
    refute_includes response.body, "foreign-payload-marker"

    get nested_attempt_path(@own_endpoint, @own_attempt)
    assert_response :success
    assert_includes response.body, "own-payload-marker"
  end

  test "stuck card value, oldest wait, and chart stay on the current root" do
    travel_to Time.zone.local(2026, 11, 16, 12, 0, 0) do
      own_due_at = Time.current - RecordingStudioWebhooks::Metrics::STUCK_RETRY_GRACE - 2.minutes
      foreign_due_at = Time.current - 2.hours
      5.times { create_stuck_attempt!(@own_endpoint, "localprov.stuck", own_due_at) }
      5.times { create_stuck_attempt!(@foreign_endpoint, "foreignprov.stuck", foreign_due_at) }

      context = admin_context
      resolved = RecordingStudioWebhooks::Admin::MetricWidgets.ensure_stuck_widget!.resolve(context)
      screen_count = RecordingStudioWebhooks::Metrics::STUCK.call(
        RecordingStudioWebhooks::AdminWebhooksTrafficDefinition.action_attempt_relation(context)
      ).count
      expected_age = (Time.current - own_due_at).floor

      assert_equal 5, screen_count
      assert_equal screen_count, resolved.value
      assert_equal "Oldest wait is #{expected_age} seconds past due.", resolved.info
      assert_equal ["localprov.stuck"], stuck_series_labels(resolved)
      assert_equal 5, stuck_series_total(resolved)

      sign_in @viewer
      get "/admin/sections/admin_webhooks"
      assert_response :success
      assert_includes response.body, "localprov.stuck"
      refute_includes response.body, "foreignprov.stuck"

      period = RecordingStudioAdmin::Period.from_preset_key(:last_4_weeks)
      get "/admin/screens/action_attempts/table", params: {
        stuck: "1",
        date_range_preset: "last_4_weeks",
        start_date: period.start_date.iso8601,
        end_date: period.end_date.iso8601
      }
      assert_response :success
      assert_equal 5, response.body.scan("localprov.stuck").size
      refute_includes response.body, "foreignprov.stuck"
    end
  end

  test "provider, endpoint, and action filters list only the current root's current endpoints" do
    context = admin_context

    FILTER_SCREENS.each do |screen_key|
      endpoint_options = dropdown_values(screen_key, :endpoint, context)
      assert_includes endpoint_options, "Current local endpoint", "#{screen_key} endpoint options"
      refute_includes endpoint_options, "Retired local endpoint", "#{screen_key} endpoint options"
      refute_includes endpoint_options, "Foreign root endpoint", "#{screen_key} endpoint options"
    end

    %w[webhook_traffic endpoints action_attempts tokens].each do |screen_key|
      provider_options = dropdown_values(screen_key, :provider, context)
      assert_includes provider_options, "localprov", "#{screen_key} provider options"
      refute_includes provider_options, "foreignprov", "#{screen_key} provider options"
    end

    action_options = dropdown_values("action_attempts", :action_name, context)
    assert_includes action_options, "localprov.kept"
    refute_includes action_options, "localprov.retired"
    refute_includes action_options, "foreignprov.secret"

    sign_in @viewer
    FILTER_SCREENS.each do |screen_key|
      get "/admin/screens/#{screen_key}"
      assert_response :success
      assert_includes response.body, "Current local endpoint"
      refute_includes response.body, "Retired local endpoint"
      refute_includes response.body, "Foreign root endpoint"
      refute_includes response.body, "foreignprov"
    end
  end

  private

  def create_user!(role)
    User.create!(
      email: "#{role}-#{SecureRandom.hex(4)}@admin.com",
      password: "Password123!",
      password_confirmation: "Password123!"
    )
  end

  def create_root!(name, actor)
    workspace = Workspace.create!(name: name)
    recording = RecordingStudio.create_root_recording!(workspace, actor: actor)
    result = RecordingStudioAccessible.bootstrap_owner_access!(recording: recording, actor: actor)
    raise result.error if result.failure?

    recording
  end

  def grant_view!(recording, actor, manager:)
    result = RecordingStudioAccessible.grant_access(
      recording: recording,
      actor: actor,
      role: :view,
      manager_actor: manager
    )
    raise result.error if result.failure?
  end

  def create_endpoint!(recording, actor, label:, provider_name:)
    RecordingStudioWebhooks::EndpointLifecycle.create!(
      endpoint: RecordingStudioWebhooks::Endpoint.new(
        recording_studio_recording_id: recording.id,
        label: label,
        provider_name: provider_name,
        identity: {},
        metadata: {},
        policy_overrides: {}
      ),
      actor: actor
    )
  end

  def create_attempt!(endpoint, token, action_name:, payload_marker:, history_marker:)
    event = RecordingStudioWebhooks::InboundEvent.create!(
      endpoint: endpoint,
      endpoint_token: token,
      provider_name: endpoint.provider_name,
      event_type: "invoice.recorded",
      provider_event_id: "evt_#{SecureRandom.hex(6)}",
      payload_digest: SecureRandom.hex(16),
      deduplication_key: "event:#{SecureRandom.uuid}",
      payload: { "type" => "invoice.recorded", "marker" => payload_marker },
      provenance: { "request_id" => SecureRandom.uuid },
      endpoint_snapshot: endpoint.snapshot,
      token_snapshot: token.snapshot,
      policy_snapshot: { "values" => RecordingStudioWebhooks::Policy.default.to_h },
      received_at: Time.current,
      status: "accepted"
    )
    event.action_attempts.create!(
      action_name: action_name,
      execution_position: 0,
      status: "succeeded",
      attempts: 1,
      completed_at: Time.current,
      last_error: nil,
      endpoint_snapshot: event.endpoint_snapshot,
      token_snapshot: event.token_snapshot,
      policy_snapshot: event.policy_snapshot,
      action_snapshot: { "name" => action_name },
      attempt_history: [
        {
          "attempt" => 1,
          "status" => "succeeded",
          "at" => Time.current.iso8601,
          "error" => history_marker
        }
      ]
    )
  end

  def create_stuck_attempt!(endpoint, action_name, due_at)
    token = endpoint.endpoint_tokens.order(:created_at).last || endpoint.issue_token!(actor: Current.actor).endpoint_token
    event = RecordingStudioWebhooks::InboundEvent.create!(
      endpoint: endpoint,
      endpoint_token: token,
      provider_name: endpoint.provider_name,
      event_type: "invoice.retry",
      provider_event_id: "evt_#{SecureRandom.hex(6)}",
      payload_digest: SecureRandom.hex(16),
      deduplication_key: "event:#{SecureRandom.uuid}",
      payload: { "type" => "invoice.retry" },
      provenance: { "request_id" => SecureRandom.uuid },
      endpoint_snapshot: endpoint.snapshot,
      token_snapshot: token.snapshot,
      policy_snapshot: { "values" => RecordingStudioWebhooks::Policy.default.to_h },
      received_at: Time.current,
      status: "accepted"
    )
    attempt = event.action_attempts.create!(
      action_name: action_name,
      execution_position: 0,
      status: "retrying",
      attempts: 1,
      completed_at: nil,
      last_error: nil,
      endpoint_snapshot: event.endpoint_snapshot,
      token_snapshot: event.token_snapshot,
      policy_snapshot: event.policy_snapshot,
      action_snapshot: { "name" => action_name },
      attempt_history: []
    )
    attempt.update_columns(next_attempt_at: due_at)
    attempt
  end

  def nested_attempt_path(endpoint, attempt)
    event = attempt.inbound_event
    "/admin/webhooks/endpoints/#{endpoint.id}/events/#{event.id}/action_attempts/#{attempt.id}"
  end

  def admin_context
    root = @own_root
    controller = Object.new
    controller.define_singleton_method(:current_root_recording) { root }
    RecordingStudioAdmin::Context.new(controller: controller, current_actor: @viewer)
  end

  def dropdown_values(screen_key, filter_key, context)
    screen = RecordingStudioAdmin.screen_for(screen_key)
    filter = screen.filters.find { |entry| entry.key == filter_key }
    assert filter, "#{screen_key} is missing #{filter_key}"
    filter.allowed_values(context)
  end

  def stuck_series_labels(resolved)
    Array(resolved.series).flat_map do |series|
      Array(series[:data] || series["data"]).map { |point| (point[:x] || point["x"]).to_s }
    end
  end

  def stuck_series_total(resolved)
    Array(resolved.series).sum do |series|
      Array(series[:data] || series["data"]).sum { |point| (point[:y] || point["y"]).to_i }
    end
  end
end
