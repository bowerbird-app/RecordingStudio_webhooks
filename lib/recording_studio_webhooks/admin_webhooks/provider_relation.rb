# frozen_string_literal: true

module RecordingStudioWebhooks
  module AdminWebhooksTrafficDefinition
    module_function

    def endpoint_token_relation(context)
      root_recording = context.root_recording
      return EndpointToken.none unless root_recording

      EndpointToken.stable
                   .joins(endpoint: :recording_studio_recording)
                   .where(recording_studio_recordings: { root_recording_id: root_recording.id })
                   .includes(:endpoint)
    end

    def token_widget_rows(context)
      endpoint_token_relation(context)
        .order(created_at: :desc)
        .limit(5)
        .map do |token|
          {
            token_id: token.id,
            endpoint_label: token.endpoint&.label.to_s,
            provider_name: token.endpoint&.provider_name.to_s,
            created_at: token.created_at,
            state: endpoint_token_state(token)
          }
        end
    end

    def token_widget_items(context)
      token_widget_rows(context).map do |row|
        state = row.fetch(:state, "unknown")
        {
          text: row.fetch(:endpoint_label, "Unknown endpoint"),
          trailing: token_widget_status_badge(context, state),
          href: "/admin/screens/tokens"
        }
      end
    end

    def token_widget_link(_context)
      "/admin/screens/tokens"
    end

    def provider_screen_relation(context)
      root_recording = context.root_recording
      return Endpoint.none unless root_recording

      quoted_root_id = ActiveRecord::Base.connection.quote(root_recording.id)

      Endpoint.current
              .joins(:recording_studio_recording)
              .where(recording_studio_recordings: { root_recording_id: root_recording.id })
              .group("recording_studio_webhooks_endpoints.provider_name")
              .select(
                <<~SQL.squish
                  recording_studio_webhooks_endpoints.provider_name AS provider_name,
                  COUNT(DISTINCT recording_studio_webhooks_endpoints.id) AS endpoints_count,
                  COUNT(DISTINCT CASE
                    WHEN recording_studio_webhooks_endpoints.enabled THEN recording_studio_webhooks_endpoints.id
                  END) AS enabled_endpoints_count,
                  (
                    SELECT COUNT(*)
                    FROM recording_studio_webhooks_inbound_events provider_events
                    INNER JOIN recording_studio_webhooks_endpoints provider_event_endpoints
                      ON provider_event_endpoints.id = provider_events.endpoint_id
                    INNER JOIN recording_studio_recordings provider_event_recordings
                      ON provider_event_recordings.id = provider_event_endpoints.recording_studio_recording_id
                    WHERE provider_event_recordings.root_recording_id = #{quoted_root_id}
                      AND provider_events.provider_name = recording_studio_webhooks_endpoints.provider_name
                  ) AS events_count,
                  (
                    SELECT MIN(provider_events.received_at)
                    FROM recording_studio_webhooks_inbound_events provider_events
                    INNER JOIN recording_studio_webhooks_endpoints provider_event_endpoints
                      ON provider_event_endpoints.id = provider_events.endpoint_id
                    INNER JOIN recording_studio_recordings provider_event_recordings
                      ON provider_event_recordings.id = provider_event_endpoints.recording_studio_recording_id
                    WHERE provider_event_recordings.root_recording_id = #{quoted_root_id}
                      AND provider_events.provider_name = recording_studio_webhooks_endpoints.provider_name
                  ) AS first_event_at,
                  (
                    SELECT MAX(provider_events.received_at)
                    FROM recording_studio_webhooks_inbound_events provider_events
                    INNER JOIN recording_studio_webhooks_endpoints provider_event_endpoints
                      ON provider_event_endpoints.id = provider_events.endpoint_id
                    INNER JOIN recording_studio_recordings provider_event_recordings
                      ON provider_event_recordings.id = provider_event_endpoints.recording_studio_recording_id
                    WHERE provider_event_recordings.root_recording_id = #{quoted_root_id}
                      AND provider_events.provider_name = recording_studio_webhooks_endpoints.provider_name
                  ) AS last_event_at
                SQL
              )
    end
  end
end
