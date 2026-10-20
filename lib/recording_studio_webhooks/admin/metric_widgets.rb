# frozen_string_literal: true

module RecordingStudioWebhooks
  module Admin
    module MetricWidgets
      STUCK_KEY = "widgets.admin_webhooks.stuck_retries"
      FAILED_KEY = "widgets.admin_webhooks.action_errors"
      CHART_OPTIONS = {
        height: 220,
        xaxis: { labels: { show: false }, axisBorder: { show: false }, axisTicks: { show: false } },
        yaxis: { labels: { show: false } },
        grid: { show: false }
      }.freeze

      STUCK = proc do
        type :chart
        title "Stuck retries"
        description "Retries that should already have run, by action."
        info { |context| MetricQuery.oldest_stuck_info(context) }
        change_good_when :down
        hide_change
        value { |context| MetricQuery.scalar(MetricQuery::STUCK, context) }
        chart_type :bar
        series { |context| MetricQuery.stuck_series(context) }
        chart_options { CHART_OPTIONS }
        link_to { |context| "#{context.admin_screen_path('action_attempts')}?stuck=1" }
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

      module_function

      def ensure_stuck_widget!
        define_widget(:AdminWebhooksStuckRetriesWidget, STUCK_KEY, &STUCK)
      end

      def ensure_failed_widget!
        define_widget(:AdminWebhooksActionErrorsWidget, FAILED_KEY, &FAILED)
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
