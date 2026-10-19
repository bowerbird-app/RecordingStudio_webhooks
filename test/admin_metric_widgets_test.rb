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
    assert_includes query, "webhook_attempts.stuck"
    assert_includes query, "webhook_attempts.oldest_stuck_age"
    assert_includes query, "webhook_attempts.failed_over_time"
    assert_includes query, "webhook_events.by_status"
    assert_includes query, "interval: \"week\""
    assert_includes query, "scope: :site"
    assert_includes query, "site_authorized: true"
    refute_includes query, "action_error_relation"
    refute_includes widgets, "action_error_relation"
    refute_includes section, "ensure_action_errors_widget_definition!"
    refute_includes section, "action_error_relation"
    assert_includes registration, "MetricWidgets.ensure_failed_widget!"
    assert_includes registration, "MetricWidgets.ensure_stuck_widget!"
    assert_includes registration, "MetricWidgets.ensure_event_status_widget!"
    assert_includes registration, "defined?(::RecordingStudioAdmin)"
    refute_includes gemspec, "recording_studio_admin"
  end
end
