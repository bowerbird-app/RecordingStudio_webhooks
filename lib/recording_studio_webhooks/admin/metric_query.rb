# frozen_string_literal: true

module RecordingStudioWebhooks
  module Admin
    module MetricQuery
      STUCK = "webhook_attempts.stuck"
      OLDEST_STUCK_AGE = "webhook_attempts.oldest_stuck_age"
      FAILED_OVER_TIME = "webhook_attempts.failed_over_time"
      EVENTS_BY_STATUS = "webhook_events.by_status"
      SITE = { scope: :site, site_authorized: true }.freeze

      module_function

      def scalar(identifier, admin_context, **params)
        result = execute(identifier, admin_context, **params)
        result ? result.value.to_i : 0
      end

      def oldest_stuck_info(admin_context)
        seconds = execute(OLDEST_STUCK_AGE, admin_context)&.value
        return "Nothing is stuck." if seconds.nil?

        "Oldest wait is #{seconds.to_i} seconds past due."
      end

      def stuck_series(admin_context)
        result = grouped_execute(STUCK, admin_context, group_by: "action_name")
        points = Array(result&.groups).map do |row|
          { x: (row[:key] || row["key"]).to_s, y: (row[:value] || row["value"]).to_i }
        end
        other = other_bucket_value(result)
        points << { x: "other", y: other } if other.positive?
        [{ name: "Stuck retries", data: points }]
      end

      def other_bucket_value(result)
        other = result&.other
        return 0 if other.nil?
        return other.to_i unless other.respond_to?(:[])

        (other[:value] || other["value"]).to_i
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

        return result.value.to_i if result.respond_to?(:value) && !result.value.nil?

        Array(result.data).sum { |row| (row[:value] || row["value"]).to_i }
      end

      def failed_series(admin_context, range)
        points = Array(execute_failed(admin_context, range)&.data).map do |row|
          { x: (row[:date] || row["date"]).to_s, y: (row[:value] || row["value"]).to_i }
        end
        [{ name: "Failed attempts", data: points }]
      end

      def event_status_items(admin_context)
        Array(execute(EVENTS_BY_STATUS, admin_context)&.data).map do |row|
          { text: (row[:key] || row["key"]).to_s.tr("_", " "), trailing: (row[:value] || row["value"]).to_i.to_s }
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

      def grouped_execute(identifier, admin_context, group_by:)
        return unless defined?(RecordingStudioMetrics::Admin)

        context = RecordingStudioMetrics::Admin.context_from_admin(admin_context, **SITE)
        RecordingStudioMetrics.execute(identifier, context: context, group_by: group_by)
      rescue RecordingStudioMetrics::Errors::AuthorizationError
        nil
      end
    end
  end
end
