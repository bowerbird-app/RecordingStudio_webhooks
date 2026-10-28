# frozen_string_literal: true

module RecordingStudioWebhooks
  module AdminWebhooksTrafficDefinition
    module_function

    def ensure_endpoints_screen_class!
      if RecordingStudioWebhooks.const_defined?(:AdminWebhooksEndpointsScreen, false)
        return RecordingStudioWebhooks.const_get(:AdminWebhooksEndpointsScreen)
      end

      screen_class = Class.new(::RecordingStudioAdmin::Screen) do
        key "endpoints"
        title "Endpoints"
        subtitle "Managed endpoint identities under Admin Webhooks providers."
        blast_radius :root

        button :new_endpoint,
               text: "New endpoint",
               style: :primary,
               url: ->(_context) { "/admin/webhooks/endpoints/new" }

        query do |context|
          root_recording = context.root_recording
          if root_recording
            Endpoint.current
                    .joins(:recording_studio_recording)
                    .where(recording_studio_recordings: { root_recording_id: root_recording.id })
                    .includes(:endpoint_tokens)
          else
            Endpoint.none
          end
        end
        filter :provider,
               options: -> { AdminWebhooksTrafficDefinition.provider_filter_values },
               apply: lambda { |relation, value, _context|
                 relation.where(provider_name: value)
               }
        filter :endpoint,
               options: -> { AdminWebhooksTrafficDefinition.endpoint_filter_values },
               apply: lambda { |relation, value, _context|
                 relation.where(label: value)
               }
        filter :status,
               values: -> { AdminWebhooksTrafficDefinition.endpoint_status_filter_values },
               apply: lambda { |relation, value, _context|
                 enabled = value.to_s == "enabled"
                 relation.where(enabled: enabled)
               }
        filter_presentation :inline

        table do
          title "Endpoints"
          filter :search,
                 apply: lambda { |relation, value, _context|
                   next relation unless value.present?

                   query = "%#{ActiveRecord::Base.sanitize_sql_like(value)}%"
                   relation.where(
                     "recording_studio_webhooks_endpoints.label ILIKE :q OR recording_studio_webhooks_endpoints.provider_name ILIKE :q",
                     q: query
                   )
                 }
          column :label,
                 value: lambda { |endpoint, _context|
                   AdminWebhooksTrafficDefinition.truncated_endpoint_label(endpoint.label)
                 },
                 tooltip: lambda { |endpoint, _context|
                   AdminWebhooksTrafficDefinition.endpoint_label_tooltip(endpoint.label)
                 }
          column :endpoint_path,
                 title: "URL",
                 sortable: false,
                 value: lambda { |endpoint, _context|
                   AdminWebhooksTrafficDefinition.endpoint_inbound_path(endpoint)
                 }
          column :provider_name, title: "Provider"
          column :activity,
                 title: "Activity",
                 sortable: false,
                 value: lambda { |endpoint, context|
                   AdminWebhooksTrafficDefinition.endpoint_activity_mini_chart(endpoint, context)
                 }
          column :enabled,
                 title: "Status",
                 sortable: false,
                 value: lambda { |endpoint, context|
                   AdminWebhooksTrafficDefinition.endpoint_status_switch(endpoint, context)
                 }
          action :copy_url,
                 text: "Copy URL",
                 url: lambda { |endpoint, context|
                   copy_value = AdminWebhooksTrafficDefinition.endpoint_inbound_url(endpoint, context)
                   next "#" if copy_value.blank?

                   current_path = context.view_context&.request&.fullpath.to_s
                   current_path = "/admin/screens/endpoints" if current_path.blank?
                   "#{current_path}#copy-url=#{CGI.escape(copy_value)}"
                 },
                 visible_if: lambda { |endpoint, context|
                   AdminWebhooksTrafficDefinition.endpoint_inbound_url(endpoint, context).present?
                 }
          action :tokens,
                 text: "Tokens",
                 url: lambda { |endpoint|
                   "/admin/screens/tokens?#{{ provider: endpoint.provider_name, endpoint: endpoint.label }.to_query}"
                 }
          default_columns :label, :endpoint_path, :provider_name, :activity, :enabled
          default_sort :created_at, direction: :desc
          paginate per_page: 25, mode: :infinite
        end
      end

      RecordingStudioWebhooks.const_set(:AdminWebhooksEndpointsScreen, screen_class)
    end

    def ensure_endpoint_widget_definition!
      if RecordingStudioWebhooks.const_defined?(:AdminWebhooksEndpointsWidget, false)
        return RecordingStudioWebhooks.const_get(:AdminWebhooksEndpointsWidget)
      end

      widget = ::RecordingStudioAdmin::Widget.new("widgets.admin_webhooks.endpoints") do
        type :list
        title "Recently Used Endpoints"
        description "Most recently used endpoints in this workspace."
        list_options divider: true, hover: true, compact_preview: :text_summary
        hide_change
        hide_metric
        items do |context|
          AdminWebhooksTrafficDefinition.endpoint_widget_items(context)
        end
        rows do |context|
          AdminWebhooksTrafficDefinition.endpoint_widget_rows(context)
        end
        link_to do |context|
          AdminWebhooksTrafficDefinition.endpoint_widget_link(context)
        end
      end

      RecordingStudioWebhooks.const_set(:AdminWebhooksEndpointsWidget, widget)
    end
  end
end
