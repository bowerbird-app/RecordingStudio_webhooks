# frozen_string_literal: true

module RecordingStudioWebhooks
  module AdminWebhooksTrafficDefinition
    module_function

    def weekly_range(reference_time = Time.current)
      reference_time.beginning_of_week..reference_time.end_of_week
    end

    def previous_weekly_range(reference_time = Time.current)
      prior_reference = reference_time - 1.week
      prior_reference.beginning_of_week..prior_reference.end_of_week
    end

    def trailing_4_week_range(reference_time = Time.current)
      end_date = reference_time.to_date
      start_date = end_date - 27.days

      start_date.beginning_of_day..end_date.end_of_day
    end

    def last_4_weeks_range(reference_time = Time.current)
      period = RecordingStudioAdmin::Period.from_preset_key(:last_4_weeks, reference_date: reference_time.to_date)
      period.start_date.beginning_of_day..period.end_date.end_of_day
    end

    def previous_trailing_4_week_range(reference_time = Time.current)
      current_start_date = reference_time.to_date - 27.days
      previous_end_date = current_start_date - 1.day
      previous_start_date = previous_end_date - 27.days

      previous_start_date.beginning_of_day..previous_end_date.end_of_day
    end

    def previous_last_4_weeks_range(reference_time = Time.current)
      current = last_4_weeks_range(reference_time)
      span_days = (current.end.to_date - current.begin.to_date).to_i
      previous_end = current.begin.to_date - 1
      previous_start = previous_end - span_days

      previous_start.beginning_of_day..previous_end.end_of_day
    end

    def percent_change_label(current_count:, previous_count:)
      return "0%" if current_count.zero? && previous_count.zero?
      return "+100%" if previous_count.zero? && current_count.positive?

      percent_change = ((current_count - previous_count) / previous_count.to_f) * 100
      format("%+.0f%%", percent_change)
    end

    def date_series(relation, frequency)
      bucket = frequency.to_sym
      expression = case bucket
                   when :hour then "DATE_TRUNC('hour', received_at)"
                   when :week then "DATE_TRUNC('week', received_at)"
                   when :month then "DATE_TRUNC('month', received_at)"
                   else "DATE(received_at)"
                   end
      grouped = Arel.sql(expression)

      relation.except(:order).group(grouped).order(grouped).count.map do |timestamp, count|
        { x: format_bucket(timestamp, bucket), y: count }
      end
    end

    def action_attempt_date_series(relation, frequency, field: :created_at)
      bucket = frequency.to_sym
      timestamp = %i[created_at completed_at].include?(field.to_sym) ? field.to_s : "created_at"
      column = "recording_studio_webhooks_action_attempts.#{timestamp}"
      expression = case bucket
                   when :hour then "DATE_TRUNC('hour', #{column})"
                   when :week then "DATE_TRUNC('week', #{column})"
                   when :month then "DATE_TRUNC('month', #{column})"
                   else "DATE(#{column})"
                   end
      grouped = Arel.sql(expression)

      chart_count_relation(relation)
        .where.not(recording_studio_webhooks_action_attempts: { timestamp => nil })
        .group(grouped)
        .order(grouped)
        .count
        .filter_map do |bucket_at, count|
        next if bucket_at.nil?

        { x: format_bucket(bucket_at, bucket), y: count.to_i }
      end
    end

    def action_attempt_chart_relation(context)
      relation = context.query_result.relation
      status = context.filter_value(:status)
      relation = relation.where(recording_studio_webhooks_action_attempts: { status: status }) if status.present?
      relation
    end

    def chart_count_relation(relation)
      return relation unless relation.respond_to?(:unscope)

      relation.unscope(:includes, :eager_load, :preload, :order)
    end

    def format_bucket(timestamp, frequency)
      value = timestamp.respond_to?(:in_time_zone) ? timestamp.in_time_zone : Time.zone.parse(timestamp.to_s)

      case frequency
      when :hour then value.strftime("%-l%P").strip
      when :week then "Week of #{value.strftime('%b %-d')}"
      when :month then value.strftime("%b")
      else value.strftime("%b %-d")
      end
    end
  end
end
