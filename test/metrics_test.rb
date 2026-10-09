# frozen_string_literal: true

require_relative "test_helper"

class MetricsTest < Minitest::Test
  def test_metrics_register_with_operations_expose_and_staff_view
    metrics = File.read(File.expand_path("../lib/recording_studio_webhooks/metrics.rb", __dir__))
    engine = File.read(File.expand_path("../lib/recording_studio_webhooks/engine.rb", __dir__))
    gemspec = File.read(File.expand_path("../recording_studio_webhooks.gemspec", __dir__))
    dummy_metrics = File.read(File.expand_path("dummy/config/initializers/recording_studio_metrics.rb", __dir__))

    assert_includes metrics, "RecordingStudioMetrics.register"
    assert_includes metrics, ":webhook_events"
    assert_includes metrics, "RecordingStudioWebhooks::InboundEvent"
    assert_includes metrics, "timeseries :over_time"
    assert_includes metrics, "field: :received_at"
    assert_includes metrics, "breakdown :by_provider"
    assert_includes metrics, "field: :provider_name"
    assert_includes metrics, ":webhook_attempts"
    assert_includes metrics, "breakdown :by_status"
    assert_includes metrics, "field: :status"
    assert_includes metrics, ":webhook_endpoints"
    assert_includes metrics, "count :enabled"
    assert_includes metrics, "relation.where(enabled: true)"
    assert_includes metrics, "Endpoint.current"
    assert_includes metrics, "blast_radius: :site"
    assert_includes metrics, "expose: EXPOSE"
    assert_includes metrics, "api: [API]"
    assert_includes metrics, "API = :operations"
    assert_includes metrics, "Api::Access.can_view?"
    refute_includes metrics, "RecordingStudioMetrics::Api.register!"
    refute_includes metrics, "prepend_view_path"
    refute_includes metrics, "respond_to?"
    refute_includes metrics, "rescue"

    assert_includes engine, 'initializer "recording_studio_webhooks.metrics"'
    assert_includes engine, "RecordingStudioWebhooks::Metrics.register!"
    refute_includes engine, "RecordingStudioMetrics::Api.register!"

    assert_includes gemspec, 'spec.add_dependency "recording_studio_metrics", "~> 0.2"'
    refute_includes dummy_metrics, "RecordingStudioMetrics::Api.register!"
  end
end
