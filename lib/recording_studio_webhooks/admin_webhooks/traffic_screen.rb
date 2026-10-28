# frozen_string_literal: true

module RecordingStudioWebhooks
  module AdminWebhooksTrafficDefinition
    module_function

    def ensure_screen_class!
      return if RecordingStudioWebhooks.const_defined?(:AdminWebhooksTrafficScreen, false)

      screen_class = Class.new(::RecordingStudioAdmin::Screen) do
        key "webhook_traffic"
        icon :chart_bar
        title "Webhook traffic"
        subtitle "Inspect inbound webhook volume for the current workspace."
        blast_radius :root

        query do |context|
          AdminWebhooksTrafficDefinition.traffic_events(context).preload(:action_attempts)
        end
        filter :date_range, field: :received_at, default: :last_4_weeks
        filter :group_by, values: FILTERABLE_GROUPINGS, default: :day
        filter :status,
               options: -> { AdminWebhooksTrafficDefinition.event_status_filter_values },
               apply: lambda { |relation, value, _context|
                 relation.where(recording_studio_webhooks_inbound_events: { status: value })
               }
        filter :provider,
               options: -> { AdminWebhooksTrafficDefinition.provider_filter_values },
               apply: ->(relation, value, _context) { relation.where(provider_name: value) }
        filter :endpoint,
               options: -> { AdminWebhooksTrafficDefinition.endpoint_filter_values },
               apply: lambda { |relation, value, _context|
                 relation.joins(:endpoint).where(recording_studio_webhooks_endpoints: { label: value })
               }
        filter_presentation :modal, inline_count: 2

        chart do
          title "Webhook traffic"
          type :area
          series do |context|
            [{
              name: "Inbound events",
              data: AdminWebhooksTrafficDefinition.date_series(
                context.query_result.relation,
                context.filter_value(:group_by) || :day
              )
            }]
          end
        end

        table do
          title "Inbound events"
          column :received_at
          column :provider_name, title: "Provider"
          column :endpoint,
                 title: "Endpoint",
                 sortable: false,
                 value: lambda { |event, _context|
                   AdminWebhooksTrafficDefinition.truncated_endpoint_label(event.endpoint.label)
                 },
                 tooltip: lambda { |event, _context|
                   AdminWebhooksTrafficDefinition.endpoint_label_tooltip(event.endpoint.label)
                 }
          column :event_type, title: "Event type"
          column :status,
                 display: :badge,
                 display_options: lambda { |_event, _context, value|
                   {
                     text: value.to_s.humanize,
                     style: AdminWebhooksTrafficDefinition.inbound_event_status_badge_style(value),
                     size: :sm
                   }
                 }
          column :actions_count,
                 title: "Actions",
                 sortable: false,
                 value: lambda { |event, context|
                   count = event.action_attempts.size
                   event_time = event.received_at || event.created_at || Time.current
                   week_start = event_time.to_date.beginning_of_week
                   week_end = event_time.to_date.end_of_week
                   context.view_context.link_to(
                     count,
                     "/admin/screens/action_attempts?#{{
                       event_id: event.id,
                       date_range_preset: 'custom',
                       start_date: week_start.iso8601,
                       end_date: week_end.iso8601,
                       group_by: 'week'
                     }.to_query}",
                     data: { turbo_frame: "_top" }
                   )
                 }
          default_columns :received_at, :provider_name, :endpoint, :event_type, :status, :actions_count
          default_sort :received_at, direction: :desc
          paginate per_page: 25, mode: :infinite
        end
      end

      RecordingStudioWebhooks.const_set(:AdminWebhooksTrafficScreen, screen_class)
    end

    def ensure_widget_definition!
      return if RecordingStudioWebhooks.const_defined?(:AdminWebhooksTrafficWidget, false)

      widget = ::RecordingStudioAdmin::Widget.new("widgets.admin_webhooks.traffic") do
        type :chart
        title "Webhook traffic"
        description "Inbound webhook events over the last 4 weeks."
        change_good_when :up
        metadata { { period_label: "Last 4 weeks" } }
        value do |context|
          range = AdminWebhooksTrafficDefinition.trailing_4_week_range(Time.current)
          AdminWebhooksTrafficDefinition.traffic_events(context)
                                        .where(received_at: range)
                                        .count
        end
        change do |context|
          reference_time = Time.current
          relation = AdminWebhooksTrafficDefinition.traffic_events(context)
          current_count = relation.where(received_at: AdminWebhooksTrafficDefinition.trailing_4_week_range(reference_time)).count
          previous_count = relation.where(received_at: AdminWebhooksTrafficDefinition.previous_trailing_4_week_range(reference_time)).count
          AdminWebhooksTrafficDefinition.percent_change_label(current_count: current_count,
                                                              previous_count: previous_count)
        end
        chart_type :area
        series do |context|
          range = AdminWebhooksTrafficDefinition.trailing_4_week_range(Time.current)
          relation = AdminWebhooksTrafficDefinition.traffic_events(context)
                                                   .where(received_at: range)
          [{ name: "Inbound events", data: AdminWebhooksTrafficDefinition.date_series(relation, :week) }]
        end
        chart_options do
          {
            height: 220,
            xaxis: {
              labels: { show: false },
              axisBorder: { show: false },
              axisTicks: { show: false }
            },
            yaxis: {
              labels: { show: false }
            },
            grid: { show: false }
          }
        end
        link_to { |context| context.admin_screen_path("webhook_traffic") }
      end

      RecordingStudioWebhooks.const_set(:AdminWebhooksTrafficWidget, widget)
    end
  end
end
