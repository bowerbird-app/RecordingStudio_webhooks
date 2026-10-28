# frozen_string_literal: true

module RecordingStudioWebhooks
  module AdminWebhooksTrafficDefinition
    module_function

    FILTERABLE_GROUPINGS = %i[hour day week month].freeze
    ACTION_FILTER_ALL = "all"
    ENDPOINT_LABEL_TRUNCATE_LENGTH = 40

    def ensure_definitions!
      return unless defined?(::RecordingStudioAdmin::Screen) && defined?(::RecordingStudioAdmin::Widget)

      ensure_screen_class!
      ensure_endpoints_screen_class!
      ensure_provider_screen_class!
      ensure_action_attempts_screen_class!
      ensure_widget_definition!
      [RecordingStudioWebhooks::AdminWebhooksTrafficScreen, RecordingStudioWebhooks::AdminWebhooksTrafficWidget]
    end

    def traffic_events(context)
      root_recording = context.root_recording
      return InboundEvent.none unless root_recording

      endpoint_ids = Endpoint.joins(:recording_studio_recording)
                             .where(recording_studio_recordings: { root_recording_id: root_recording.id })
                             .select(:id)

      InboundEvent.includes(:endpoint).where(endpoint_id: endpoint_ids)
    end

    def provider_filter_values
      Endpoint.current.distinct.order(:provider_name).pluck(:provider_name)
    end

    def provider_widget_rows(context)
      root_recording = context.root_recording
      return [] unless root_recording

      endpoint_scope = Endpoint.current
                               .joins(:recording_studio_recording)
                               .where(recording_studio_recordings: { root_recording_id: root_recording.id })
      events_scope = traffic_events(context).where(received_at: 30.days.ago..Time.current)

      endpoint_counts = endpoint_scope.group(:provider_name).count
      enabled_counts = endpoint_scope.where(enabled: true).group(:provider_name).count
      event_counts = events_scope.group(:provider_name).count
      last_event_at = events_scope.group(:provider_name).maximum(:received_at)

      (endpoint_counts.keys | event_counts.keys).sort.map do |provider_name|
        {
          provider: provider_name,
          endpoints: endpoint_counts.fetch(provider_name, 0),
          enabled: enabled_counts.fetch(provider_name, 0),
          events_30d: event_counts.fetch(provider_name, 0),
          last_event: last_event_at[provider_name]&.in_time_zone&.strftime("%b %-d, %Y %H:%M") || "No recent events",
          provider_url: "/admin/screens/providers?#{{ provider: provider_name }.to_query}"
        }
      end
    end

    def provider_widget_items(context)
      provider_widget_rows(context).first(5).map do |row|
        endpoints_count = row[:endpoints].to_i
        {
          text: row.fetch(:provider, "Unknown"),
          href: row[:provider_url],
          trailing: "#{endpoints_count} #{endpoints_count == 1 ? 'endpoint' : 'endpoints'}"
        }
      end
    end

    def provider_widget_link(_context)
      "/admin/screens/providers"
    end
  end
end
