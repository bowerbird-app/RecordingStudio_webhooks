# frozen_string_literal: true

module RecordingStudioWebhooks
  module AdminWebhooksTrafficDefinition
    module_function

    def ensure_provider_screen_class!
      if RecordingStudioWebhooks.const_defined?(:AdminWebhooksProvidersScreen, false)
        return RecordingStudioWebhooks.const_get(:AdminWebhooksProvidersScreen)
      end

      screen_class = Class.new(::RecordingStudioAdmin::Screen) do
        key "providers"
        title "Providers"
        subtitle "Webhook providers that have been set in config."
        blast_radius :root

        query { |context| AdminWebhooksTrafficDefinition.provider_screen_relation(context) }
        filter :endpoint,
               options: -> { AdminWebhooksTrafficDefinition.endpoint_filter_values },
               apply: lambda { |relation, value, _context|
                 relation.where(recording_studio_webhooks_endpoints: { label: value })
               }
        filter_presentation :inline

        table do
          title ""
          hide_count
          filter :search,
                 apply: lambda { |relation, value, _context|
                   next relation unless value.present?

                   relation.where(
                     "recording_studio_webhooks_inbound_events.provider_name ILIKE :q",
                     q: "%#{ActiveRecord::Base.sanitize_sql_like(value)}%"
                   )
                 }
          column :provider_name, title: "Provider"
          column :enabled_endpoints_count,
                 title: "Enabled endpoints",
                 value: lambda { |row, context|
                   context.view_context.link_to(
                     row.enabled_endpoints_count.to_i,
                     "/admin/screens/endpoints?#{{ provider: row.provider_name, status: 'enabled' }.to_query}",
                     data: { turbo_frame: "_top" }
                   )
                 }
          column :events_count,
                 title: "Events",
                 value: lambda { |row, context|
                   context.view_context.link_to(
                     row.events_count.to_i,
                     AdminWebhooksTrafficDefinition.provider_traffic_url(row),
                     data: { turbo_frame: "_top" }
                   )
                 }
          column :actions_count,
                 title: "Actions",
                 sortable: false,
                 value: lambda { |row, context|
                   count = AdminWebhooksTrafficDefinition.registered_actions_count_for_provider(row.provider_name)
                   context.view_context.link_to(
                     count,
                     "/admin/screens/actions?#{{ provider: row.provider_name }.to_query}",
                     data: { turbo_frame: "_top" }
                   )
                 }
          column :last_event_at,
                 title: "Latest event",
                 value: lambda { |row, _context|
                   row.last_event_at.presence || "No recent events"
                 }
          default_columns :provider_name, :enabled_endpoints_count, :events_count, :actions_count,
                          :last_event_at
          default_sort :events_count, direction: :desc
          paginate per_page: 25, mode: :infinite
        end
      end

      RecordingStudioWebhooks.const_set(:AdminWebhooksProvidersScreen, screen_class)
    end

    def ensure_provider_widget_definition!
      if RecordingStudioWebhooks.const_defined?(:AdminWebhooksProvidersWidget, false)
        return RecordingStudioWebhooks.const_get(:AdminWebhooksProvidersWidget)
      end

      widget = ::RecordingStudioAdmin::Widget.new("widgets.admin_webhooks.providers") do
        type :list
        title "Providers"
        description "Provider health across endpoints and recent inbound traffic."
        list_options divider: true, hover: true, compact_preview: :text_summary
        hide_change
        hide_metric
        items do |context|
          AdminWebhooksTrafficDefinition.provider_widget_items(context)
        end
        rows do |context|
          AdminWebhooksTrafficDefinition.provider_widget_rows(context)
        end
        link_to do |context|
          AdminWebhooksTrafficDefinition.provider_widget_link(context)
        end
      end

      RecordingStudioWebhooks.const_set(:AdminWebhooksProvidersWidget, widget)
    end
  end
end
