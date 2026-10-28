# frozen_string_literal: true

module RecordingStudioWebhooks
  module AdminWebhooksTrafficDefinition
    module_function

    STUCK_FILTER_ON = %w[1 true yes on].freeze

    def stuck_filter_on?(value)
      STUCK_FILTER_ON.include?(value.to_s.strip.downcase)
    end

    def apply_stuck_scope(relation, value)
      return relation unless stuck_filter_on?(value)

      RecordingStudioWebhooks::Metrics::STUCK.call(relation)
    end

    def skip_completed_at_range?(context)
      stuck_filter_on?(context.filter_value(:stuck))
    end

    def action_attempt_relation(context)
      root_recording = context.root_recording
      return ActionAttempt.none unless root_recording

      endpoint_ids = Endpoint.joins(:recording_studio_recording)
                             .where(recording_studio_recordings: { root_recording_id: root_recording.id })
                             .select(:id)

      ActionAttempt
        .joins(:inbound_event)
        .where(recording_studio_webhooks_inbound_events: { endpoint_id: endpoint_ids })
        .includes(inbound_event: :endpoint)
    end

    def registered_action_rows
      RecordingStudioWebhooks.configuration.actions.all
    end

    def registered_actions_count_for_provider(provider_name)
      registered_action_rows.count do |action|
        action.provider_name.nil? || action.provider_name == provider_name
      end
    end

    def provider_traffic_url(row)
      params = { provider: row.provider_name }
      if row.first_event_at.present? && row.last_event_at.present?
        params.merge!(
          date_range_preset: "custom",
          start_date: row.first_event_at.to_date.iso8601,
          end_date: row.last_event_at.to_date.iso8601
        )
      end

      "/admin/screens/webhook_traffic?#{params.to_query}"
    end

    def endpoint_filter_values
      Endpoint.distinct.order(:label).pluck(:label)
    end

    def action_filter_values
      observed_actions = ActionAttempt.distinct.order(:action_name).pluck(:action_name).compact
      registered_actions = registered_action_rows.map(&:name).map(&:to_s).reject(&:empty?)
      action_names = (observed_actions + registered_actions).uniq.sort

      [ACTION_FILTER_ALL, *action_names]
    end

    def action_row_view_url(action, _context)
      params = { action_name: action.name }
      params[:provider] = action.provider_name if action.provider_name.present?
      "/admin/screens/action_attempts?#{params.to_query}"
    end

    def action_activity_counts_30d(action, context, reference_time = Time.current)
      end_date = reference_time.to_date
      start_date = end_date - 29.days
      counts_by_date = action_attempt_relation(context)
                       .where(action_name: action.name, created_at: start_date.beginning_of_day..end_date.end_of_day)
                       .group(Arel.sql("DATE(recording_studio_webhooks_action_attempts.created_at)"))
                       .count

      (start_date..end_date).map { |date| counts_by_date.fetch(date, 0).to_i }
    end

    def action_activity_chart(action, context)
      counts = action_activity_counts_30d(action, context)
      description = "#{counts.sum} attempts in last 30 days"

      activity_mini_chart(
        counts: counts,
        description: description,
        url: action_row_view_url(action, context),
        context: context
      )
    end

    def event_status_filter_values
      InboundEvent::STATUSES
    end

    def action_status_filter_values
      ActionAttempt::STATUSES
    end

    def endpoint_status_filter_values
      %w[enabled disabled]
    end
  end
end
