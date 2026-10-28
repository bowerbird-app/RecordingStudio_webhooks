# frozen_string_literal: true

module RecordingStudioWebhooks
  module AdminWebhooksTrafficDefinition
    module_function

    def ensure_action_attempts_screen_class!
      if RecordingStudioWebhooks.const_defined?(:AdminWebhooksActionAttemptsScreen, false)
        return RecordingStudioWebhooks.const_get(:AdminWebhooksActionAttemptsScreen)
      end

      screen_class = Class.new(::RecordingStudioAdmin::Screen) do
        key "action_attempts"
        icon :chart_bar
        title "Action attempts"
        subtitle "Inspect action execution attempts for webhook attempts in the current workspace."
        blast_radius :root

        query { |context| AdminWebhooksTrafficDefinition.action_attempt_relation(context) }
        filter :date_range, field: :completed_at, default: :last_4_weeks
        filter :stuck,
               values: %w[1],
               apply: lambda { |relation, value, _context|
                 AdminWebhooksTrafficDefinition.apply_stuck_scope(relation, value)
               }
        filter :group_by, values: FILTERABLE_GROUPINGS, default: :day
        filter :provider,
               options: -> { AdminWebhooksTrafficDefinition.provider_filter_values },
               apply: lambda { |relation, value, _context|
                 relation.where(recording_studio_webhooks_inbound_events: { provider_name: value })
               }
        filter :endpoint,
               options: -> { AdminWebhooksTrafficDefinition.endpoint_filter_values },
               apply: lambda { |relation, value, _context|
                 relation.joins(inbound_event: :endpoint)
                         .where(recording_studio_webhooks_endpoints: { label: value })
               }
        filter :action_name,
               options: -> { AdminWebhooksTrafficDefinition.action_filter_values },
               apply: lambda { |relation, value, _context|
                 selected = value.to_s

                 case selected
                 when "", ACTION_FILTER_ALL
                   relation
                 else
                   relation.where(recording_studio_webhooks_action_attempts: { action_name: selected })
                 end
               }
        filter :status,
               options: -> { AdminWebhooksTrafficDefinition.action_status_filter_values },
               apply: lambda { |relation, value, _context|
                 relation.where(recording_studio_webhooks_action_attempts: { status: value })
               }
        filter :event_id,
               apply: lambda { |relation, value, _context|
                 inbound_event_id = value.to_s.strip
                 next relation if inbound_event_id.empty?

                 relation.where(recording_studio_webhooks_action_attempts: { inbound_event_id: inbound_event_id })
               }
        filter_presentation :modal, inline_count: 2

        summary do
          label "Action attempts"
          change_good_when do |context|
            %w[failed cancelled].include?(context.filter_value(:status).to_s) ? :down : :up
          end
        end

        chart do
          title "Action attempts"
          type :area
          series do |context|
            [{
              name: "Action attempts",
              data: AdminWebhooksTrafficDefinition.action_attempt_date_series(
                AdminWebhooksTrafficDefinition.action_attempt_chart_relation(context),
                context.filter_value(:group_by) || :day,
                field: :completed_at
              )
            }]
          end
        end

        table do
          title "Action attempts"
          column :created_at
          column :action_name, title: "Action"
          column :attempts, title: "Attempts"
          column :status,
                 display: :badge,
                 display_options: lambda { |_attempt, _context, value|
                   {
                     text: value.to_s.humanize,
                     style: AdminWebhooksTrafficDefinition.action_attempt_status_badge_style(value),
                     size: :sm
                   }
                 }
          column :provider,
                 title: "Provider",
                 sortable: false,
                 value: ->(attempt, _context) { attempt.inbound_event.provider_name }
          column :endpoint,
                 title: "Endpoint",
                 sortable: false,
                 value: lambda { |attempt, _context|
                   AdminWebhooksTrafficDefinition.truncated_endpoint_label(attempt.inbound_event.endpoint.label)
                 },
                 tooltip: lambda { |attempt, _context|
                   AdminWebhooksTrafficDefinition.endpoint_label_tooltip(attempt.inbound_event.endpoint.label)
                 }
          action :view,
                 text: "View",
                 url: lambda { |attempt|
                   "/admin/webhooks/action_attempts/#{attempt.id}"
                 }
          default_columns :created_at, :action_name, :attempts, :status, :provider, :endpoint
          default_sort :created_at, direction: :desc
          paginate per_page: 25, mode: :infinite
        end
      end

      RecordingStudioWebhooks.const_set(:AdminWebhooksActionAttemptsScreen, screen_class)
    end

    def ensure_action_attempts_widget_definition!
      if RecordingStudioWebhooks.const_defined?(:AdminWebhooksActionAttemptsWidget, false)
        return RecordingStudioWebhooks.const_get(:AdminWebhooksActionAttemptsWidget)
      end

      widget = ::RecordingStudioAdmin::Widget.new("widgets.admin_webhooks.action_attempts") do
        type :chart
        title "Action attempts"
        description "Action execution attempts over the last 4 weeks."
        change_good_when :up
        metadata { { period_label: "Last 4 weeks" } }
        value do |context|
          range = AdminWebhooksTrafficDefinition.last_4_weeks_range(Time.current)
          AdminWebhooksTrafficDefinition.action_attempt_relation(context)
                                        .where(completed_at: range)
                                        .count
        end
        change do |context|
          reference_time = Time.current
          relation = AdminWebhooksTrafficDefinition.action_attempt_relation(context)
          current_count = relation.where(completed_at: AdminWebhooksTrafficDefinition.last_4_weeks_range(reference_time)).count
          previous_count = relation.where(completed_at: AdminWebhooksTrafficDefinition.previous_last_4_weeks_range(reference_time)).count
          AdminWebhooksTrafficDefinition.percent_change_label(current_count: current_count,
                                                              previous_count: previous_count)
        end
        chart_type :area
        series do |context|
          range = AdminWebhooksTrafficDefinition.last_4_weeks_range(Time.current)
          relation = AdminWebhooksTrafficDefinition.action_attempt_relation(context)
                                                   .where(completed_at: range)
          [{ name: "Action attempts",
             data: AdminWebhooksTrafficDefinition.action_attempt_date_series(relation, :week, field: :completed_at) }]
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
        link_to { |context| context.admin_screen_path("action_attempts") }
      end

      RecordingStudioWebhooks.const_set(:AdminWebhooksActionAttemptsWidget, widget)
    end
  end
end
