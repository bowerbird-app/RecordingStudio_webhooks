# frozen_string_literal: true

module RecordingStudioWebhooks
  module AdminWebhooksTrafficDefinition
    module_function

    def endpoint_widget_rows(context)
      root_recording = context.root_recording
      return [] unless root_recording

      endpoint_scope = Endpoint.current
                               .joins(:recording_studio_recording)
                               .where(recording_studio_recordings: { root_recording_id: root_recording.id })

      last_event_at_by_endpoint_id = traffic_events(context)
                                     .group(:endpoint_id)
                                     .maximum(:received_at)

      events_count_by_endpoint_id = traffic_events(context)
                                    .where(received_at: 30.days.ago..Time.current)
                                    .group(:endpoint_id)
                                    .count

      endpoint_scope.map do |endpoint|
        {
          endpoint_id: endpoint.id,
          label: endpoint.label,
          provider: endpoint.provider_name,
          last_event_at: last_event_at_by_endpoint_id[endpoint.id],
          events_30d: events_count_by_endpoint_id.fetch(endpoint.id, 0)
        }
      end.sort_by { |row| [row[:last_event_at] ? 0 : 1, -(row[:last_event_at]&.to_i || 0), row[:label].to_s] }
    end

    def endpoint_widget_items(context)
      endpoint_widget_rows(context).first(5).map do |row|
        events_count = row[:events_30d].to_i
        {
          text: row.fetch(:label, "Unknown endpoint"),
          href: "/admin/screens/endpoints",
          trailing: "#{events_count} #{events_count == 1 ? 'event' : 'events'}"
        }
      end
    end

    def endpoint_widget_link(_context)
      "/admin/screens/endpoints"
    end

    def action_widget_rows(context)
      range = trailing_4_week_range(Time.current)
      counts = action_attempt_relation(context)
               .where(status: "succeeded")
               .where(created_at: range)
               .group(:action_name)
               .count

      counts
        .map { |action_name, total| [action_name.to_s, total.to_i] }
        .sort_by { |name, total| [-total, name] }
        .first(5)
        .map do |name, total|
          {
            action_name: name,
            successful_count_4w: total,
            action_url: "/admin/screens/action_attempts?#{{ action_name: name }.to_query}"
          }
        end
    end

    def action_widget_items(context)
      action_widget_rows(context).map do |row|
        successful_count = row[:successful_count_4w].to_i
        {
          text: row.fetch(:action_name, "Unknown action"),
          href: row[:action_url],
          trailing: successful_count.to_s
        }
      end
    end

    def action_widget_link(_context)
      "/admin/screens/actions"
    end
  end
end
