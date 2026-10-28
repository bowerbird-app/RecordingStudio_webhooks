# frozen_string_literal: true

module RecordingStudioWebhooks
  module AdminWebhooksTrafficDefinition
    module_function

    def ensure_actions_screen_class!
      if RecordingStudioWebhooks.const_defined?(:AdminWebhooksActionsScreen, false)
        return RecordingStudioWebhooks.const_get(:AdminWebhooksActionsScreen)
      end

      screen_class = Class.new(::RecordingStudioAdmin::Screen) do
        key "actions"
        title "Actions"
        subtitle "Registered webhook actions available in this environment."
        blast_radius :root

        query { |_context| AdminWebhooksTrafficDefinition.registered_action_rows }
        filter :provider,
               options: lambda {
                 AdminWebhooksTrafficDefinition.registered_action_rows.map(&:provider_name).compact.uniq.sort
               },
               apply: lambda { |rows, value, _context|
                 rows.select { |action| action.provider_name.to_s == value.to_s }
               }
        filter_presentation :inline

        table do
          title "Registered actions"
          filter :search,
                 apply: lambda { |rows, value, _context|
                   query = value.to_s.strip
                   next rows if query.empty?

                   term = query.downcase
                   rows.select do |action|
                     [
                       action.name,
                       action.provider_name,
                       action.event_pattern.value,
                       action.source
                     ].compact.any? { |field| field.to_s.downcase.include?(term) }
                   end
                 }
          column :name,
                 title: "Action",
                 sortable: false,
                 value: lambda { |action, context|
                   context.view_context.link_to(
                     action.name,
                     AdminWebhooksTrafficDefinition.action_row_view_url(action, context),
                     data: { turbo_frame: "_top" }
                   )
                 }
          column :provider_name, title: "Provider", sortable: false,
                                 value: ->(action, _context) { action.provider_name.presence || "Any" }
          column :event_pattern, title: "Event pattern", sortable: false,
                                 value: ->(action, _context) { action.event_pattern.value }
          column :activity,
                 title: "Activity",
                 sortable: false,
                 value: lambda { |action, context|
                   AdminWebhooksTrafficDefinition.action_activity_chart(action, context)
                 }
          column :priority, title: "Priority", sortable: false, value: ->(action, _context) { action.priority }
          column :source, title: "Source", sortable: false, value: ->(action, _context) { action.source }
          action :view,
                 text: "View",
                 url: lambda { |action, context|
                   AdminWebhooksTrafficDefinition.action_row_view_url(action, context)
                 }
          default_columns :name, :provider_name, :event_pattern, :activity, :priority, :source
          paginate per_page: 25, mode: :infinite
        end
      end

      RecordingStudioWebhooks.const_set(:AdminWebhooksActionsScreen, screen_class)
    end

    def ensure_actions_widget_definition!
      if RecordingStudioWebhooks.const_defined?(:AdminWebhooksActionsWidget, false)
        return RecordingStudioWebhooks.const_get(:AdminWebhooksActionsWidget)
      end

      widget = ::RecordingStudioAdmin::Widget.new("widgets.admin_webhooks.actions") do
        type :list
        title "Recently Used Actions"
        description "Most-used actions over the last 4 weeks."
        list_options divider: true, hover: true, compact_preview: :text_summary
        hide_change
        hide_metric
        items do |context|
          AdminWebhooksTrafficDefinition.action_widget_items(context)
        end
        rows do |context|
          AdminWebhooksTrafficDefinition.action_widget_rows(context)
        end
        link_to do |context|
          AdminWebhooksTrafficDefinition.action_widget_link(context)
        end
      end

      RecordingStudioWebhooks.const_set(:AdminWebhooksActionsWidget, widget)
    end
  end
end
