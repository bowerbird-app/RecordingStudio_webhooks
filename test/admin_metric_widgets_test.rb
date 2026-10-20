# frozen_string_literal: true

require_relative "test_helper"

class AdminMetricWidgetsTest < Minitest::Test
  def test_metric_widgets_call_recording_studio_metrics
    query = File.read(File.expand_path("../lib/recording_studio_webhooks/admin/metric_query.rb", __dir__))
    widgets = File.read(File.expand_path("../lib/recording_studio_webhooks/admin/metric_widgets.rb", __dir__))
    registration = File.read(File.expand_path("../lib/recording_studio_webhooks/admin/registration.rb", __dir__))
    section = File.read(File.expand_path("../lib/recording_studio_webhooks/admin_webhooks_section.rb", __dir__))
    gemspec = File.read(File.expand_path("../recording_studio_webhooks.gemspec", __dir__))

    assert_includes query, "RecordingStudioMetrics::Admin.execute"
    assert_includes query, "RecordingStudioMetrics.execute"
    assert_includes query, "webhook_attempts.stuck"
    assert_includes query, "webhook_attempts.oldest_stuck_age"
    assert_includes query, "webhook_attempts.failed_over_time"
    assert_includes query, "group_by: \"action_name\""
    assert_includes query, "interval: \"week\""
    assert_includes query, "scope: :site"
    assert_includes query, "site_authorized: true"
    assert_includes query, "authorized_relation:"
    assert_includes widgets, "type :chart"
    assert_includes widgets, "chart_type :bar"
    assert_includes widgets, "MetricQuery.stuck_series"
    assert_includes widgets, "?stuck=1"
    refute_includes widgets, "EVENT_STATUS"
    refute_includes widgets, "ensure_event_status_widget!"
    assert_includes section, "action_attempts: \"Action attempts\""
    assert_includes section, "providers: \"Providers\""
    assert_includes section, "endpoints: \"Endpoints\""
    assert_includes section, "actions: \"Actions\""
    assert_includes section, "filter :date_range, field: :completed_at"
    assert_includes section, "filter :stuck"
    assert_includes section, "Metrics::STUCK.call"
    assert_includes section, "def last_4_weeks_range"
    assert_includes section, "action_attempt_chart_relation"
    assert_includes section, ".where.not(recording_studio_webhooks_action_attempts: { timestamp => nil })"
    assert_includes section, ".where(completed_at: range)"
    assert_includes section, "field: :completed_at"
    assert_includes query, "last_4_weeks_range"
    assert_includes section, "filter_presentation :modal, inline_count: 2"
    assert_includes section, "event_status_filter_values"
    refute_includes query, "action_error_relation"
    refute_includes widgets, "action_error_relation"
    refute_includes section, "ensure_action_errors_widget_definition!"
    refute_includes section, "action_error_relation"
    assert_includes registration, "MetricWidgets.ensure_failed_widget!"
    assert_includes registration, "MetricWidgets.ensure_stuck_widget!"
    refute_includes registration, "ensure_event_status_widget!"
    refute_includes section, "ensure_event_status_widget!"
    refute_includes section, '"widgets.admin_webhooks.event_status" => { view_variant: :card }'
    assert_includes registration, "defined?(::RecordingStudioAdmin)"
    refute_includes gemspec, "recording_studio_admin"
  end
end
