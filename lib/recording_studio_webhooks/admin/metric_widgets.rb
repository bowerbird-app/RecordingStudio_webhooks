# frozen_string_literal: true

module RecordingStudioWebhooks
  module Admin
    module MetricWidgets
      STUCK = "webhook_attempts.stuck"
      OLDEST_STUCK_AGE = "webhook_attempts.oldest_stuck_age"
      FAILED_OVER_TIME = "webhook_attempts.failed_over_time"
      EVENTS_BY_STATUS = "webhook_events.by_status"

      STUCK_KEY = "widgets.admin_webhooks.stuck_retries"
      FAILED_KEY = "widgets.admin_webhooks.action_errors"
      STATUS_KEY = "widgets.admin_webhooks.event_status"

      SITE = { scope: :site, site_authorized: true }.freeze
      CHART_OPTIONS = {
        height: 220,
        xaxis: {
          labels: { show: false },
          axisBorder: { show: false },
          axisTicks: { show: false }
        },
        yaxis: { labels: { show: false } },
        grid: { show: false }
      }.freeze

      module_function

      def ensure_stuck_widget!
        return unless widget_class?
        if RecordingStudioWebhooks.const_defined?(:AdminWebhooksStuckRetriesWidget, false)
          return RecordingStudioWebhooks.const_get(:AdminWebhooksStuckRetriesWidget)
        end

        widget = ::RecordingStudioAdmin::Widget.new(STUCK_KEY) do
          type :number
          title "Stuck retries"
          description "Retries that should already have run."
          info do |context|
            MetricWidgets.oldest_stuck_info(context)
          end
          change_good_when :down
          hide_change
          value do |context|
            MetricWidgets.scalar(STUCK, context)
          end
          link_to { |context| context.admin_screen_path("action_attempts") }
        end

        RecordingStudioWebhooks.const_set(:AdminWebhooksStuckRetriesWidget, widget)
      end

      def ensure_failed_widget!
        return unless widget_class?
        if RecordingStudioWebhooks.const_defined?(:AdminWebhooksActionErrorsWidget, false)
          return RecordingStudioWebhooks.const_get(:AdminWebhooksActionErrorsWidget)
        end

        widget = ::RecordingStudioAdmin::Widget.new(FAILED_KEY) do
          type :chart
          title "Failed attempts"
          description "Attempts that ended in failed, by when they finished."
          change_good_when :down
          metadata { { period_label: "Last 4 weeks" } }
          value do |context|
            MetricWidgets.failed_count(context, MetricWidgets.current_failed_window)
          end
          change do |context|
            current = MetricWidgets.failed_count(context, MetricWidgets.current_failed_window)
            previous = MetricWidgets.failed_count(context, MetricWidgets.previous_failed_window)
            AdminWebhooksTrafficDefinition.percent_change_label(
              current_count: current,
              previous_count: previous
            )
          end
          chart_type :area
          series do |context|
            MetricWidgets.failed_series(context, MetricWidgets.current_failed_window)
          end
          chart_options { CHART_OPTIONS }
          link_to do |context|
            "#{context.admin_screen_path("action_attempts")}?status=failed"
          end
        end

        RecordingStudioWebhooks.const_set(:AdminWebhooksActionErrorsWidget, widget)
      end

      def ensure_event_status_widget!
        return unless widget_class?
        if RecordingStudioWebhooks.const_defined?(:AdminWebhooksEventStatusWidget, false)
          return RecordingStudioWebhooks.const_get(:AdminWebhooksEventStatusWidget)
        end

        widget = ::RecordingStudioAdmin::Widget.new(STATUS_KEY) do
          type :list
          title "Event status"
          description "Inbound events by status."
          list_options divider: true, hover: true, compact_preview: :text_summary
          hide_change
          hide_metric
          items do |context|
            MetricWidgets.event_status_items(context)
          end
          link_to { |context| context.admin_screen_path("webhook_traffic") }
        end

        RecordingStudioWebhooks.const_set(:AdminWebhooksEventStatusWidget, widget)
      end

      def widget_class?
        defined?(::RecordingStudioAdmin::Widget)
      end

      def scalar(identifier, admin_context, **params)
        result = execute(identifier, admin_context, **params)
        result ? result.value.to_i : 0
      end

      def oldest_stuck_info(admin_context)
        result = execute(OLDEST_STUCK_AGE, admin_context)
        seconds = result&.value
        return "Nothing is stuck." if seconds.nil?

        "Oldest wait is #{seconds.to_i} seconds past due."
      end

      def current_failed_window
        AdminWebhooksTrafficDefinition.trailing_4_week_range(Time.current)
      end

      def previous_failed_window
        AdminWebhooksTrafficDefinition.previous_trailing_4_week_range(Time.current)
      end

      def failed_count(admin_context, range)
        result = execute_failed(admin_context, range)
        return 0 unless result

        if result.respond_to?(:value) && !result.value.nil?
          return result.value.to_i
        end

        Array(result.data).sum { |row| (row[:value] || row["value"]).to_i }
      end

      def failed_series(admin_context, range)
        result = execute_failed(admin_context, range)
        points = Array(result&.data).map do |row|
          date = row[:date] || row["date"]
          value = row[:value] || row["value"]
          { x: date.to_s, y: value.to_i }
        end
        [{ name: "Failed attempts", data: points }]
      end

      def event_status_items(admin_context)
        result = execute(EVENTS_BY_STATUS, admin_context)
        Array(result&.data).map do |row|
          key = row[:key] || row["key"]
          value = row[:value] || row["value"]
          {
            text: key.to_s.tr("_", " "),
            trailing: value.to_i.to_s
          }
        end
      end

      def execute_failed(admin_context, range)
        execute(
          FAILED_OVER_TIME,
          admin_context,
          interval: "week",
          start_at: range.begin,
          end_at: exclusive_end(range)
        )
      end

      def exclusive_end(range)
        range.end.respond_to?(:beginning_of_day) ? range.end.beginning_of_day + 1.day : range.end
      end

      def execute(identifier, admin_context, **params)
        return unless defined?(RecordingStudioMetrics::Admin)

        RecordingStudioMetrics::Admin.execute(
          identifier,
          admin_context: admin_context,
          **SITE,
          **params
        )
      rescue RecordingStudioMetrics::Errors::AuthorizationError
        nil
      end
    end
  end
end
