# frozen_string_literal: true

module RecordingStudioWebhooks
  module Admin
    module MetricWidgets
      STUCK_KEY = "widgets.admin_webhooks.stuck_retries"
      FAILED_KEY = "widgets.admin_webhooks.action_errors"
      STATUS_KEY = "widgets.admin_webhooks.event_status"
      CHART_OPTIONS = {
        height: 220,
        xaxis: { labels: { show: false }, axisBorder: { show: false }, axisTicks: { show: false } },
        yaxis: { labels: { show: false } },
        grid: { show: false }
      }.freeze

      STUCK = proc do
        type :number
        title "Stuck retries"
        description "Retries that should already have run."
        info { |context| MetricQuery.oldest_stuck_info(context) }
        change_good_when :down
        hide_change
        value { |context| MetricQuery.scalar(MetricQuery::STUCK, context) }
        link_to { |context| context.admin_screen_path("action_attempts") }
      end

      FAILED = proc do
        type :chart
        title "Failed attempts"
        description "Attempts that ended in failed, by when they finished."
        change_good_when :down
        metadata { { period_label: "Last 4 weeks" } }
        value { |context| MetricQuery.failed_count(context, MetricQuery.current_failed_window) }
        change { |context| MetricWidgets.failed_change(context) }
        chart_type :area
        series { |context| MetricQuery.failed_series(context, MetricQuery.current_failed_window) }
        chart_options { CHART_OPTIONS }
        link_to { |context| "#{context.admin_screen_path('action_attempts')}?status=failed" }
      end

      EVENT_STATUS = proc do
        type :list
        title "Event status"
        description "Inbound events by status."
        list_options divider: true, hover: true, compact_preview: :text_summary
        hide_change
        hide_metric
        items { |context| MetricQuery.event_status_items(context) }
        link_to { |context| context.admin_screen_path("webhook_traffic") }
      end

      module_function

      def ensure_stuck_widget!
        define_widget(:AdminWebhooksStuckRetriesWidget, STUCK_KEY, &STUCK)
      end

      def ensure_failed_widget!
        define_widget(:AdminWebhooksActionErrorsWidget, FAILED_KEY, &FAILED)
      end

      def ensure_event_status_widget!
        define_widget(:AdminWebhooksEventStatusWidget, STATUS_KEY, &EVENT_STATUS)
      end

      def failed_change(context)
        AdminWebhooksTrafficDefinition.percent_change_label(
          current_count: MetricQuery.failed_count(context, MetricQuery.current_failed_window),
          previous_count: MetricQuery.failed_count(context, MetricQuery.previous_failed_window)
        )
      end

      def define_widget(const_name, key, &)
        return unless defined?(::RecordingStudioAdmin::Widget)
        if RecordingStudioWebhooks.const_defined?(const_name, false)
          return RecordingStudioWebhooks.const_get(const_name)
        end

        RecordingStudioWebhooks.const_set(const_name, ::RecordingStudioAdmin::Widget.new(key, &))
      end
    end
  end
end
