# frozen_string_literal: true

module RecordingStudioWebhooks
  module AdminWebhooksTrafficDefinition
    module_function

    def ensure_tokens_screen_class!
      if RecordingStudioWebhooks.const_defined?(:AdminWebhooksTokensScreen, false)
        return RecordingStudioWebhooks.const_get(:AdminWebhooksTokensScreen)
      end

      screen_class = Class.new(::RecordingStudioAdmin::Screen) do
        key "tokens"
        title "Tokens"
        subtitle "Recent webhook endpoint tokens in this workspace."
        blast_radius :root

        button :new_token,
               text: "New token",
               style: :primary,
               url: ->(_context) { "/admin/webhooks/tokens/new" }

        query { |context| AdminWebhooksTrafficDefinition.endpoint_token_relation(context) }
        filter :provider,
               options: -> { AdminWebhooksTrafficDefinition.provider_filter_values },
               apply: lambda { |relation, value, _context|
                 relation.where(recording_studio_webhooks_endpoints: { provider_name: value })
               }
        filter :endpoint,
               options: -> { AdminWebhooksTrafficDefinition.endpoint_filter_values },
               apply: lambda { |relation, value, _context|
                 relation.where(recording_studio_webhooks_endpoints: { label: value })
               }
        filter_presentation :inline

        table do
          title "Recent tokens"
          column :created_at
          column :provider,
                 title: "Provider",
                 sortable: false,
                 value: ->(token, _context) { token.endpoint&.provider_name.to_s }
          column :endpoint,
                 title: "Endpoint",
                 sortable: false,
                 value: lambda { |token, _context|
                   AdminWebhooksTrafficDefinition.truncated_endpoint_label(token.endpoint&.label.to_s)
                 },
                 tooltip: lambda { |token, _context|
                   AdminWebhooksTrafficDefinition.endpoint_label_tooltip(token.endpoint&.label.to_s)
                 }
          column :prefix, title: "Token"
          column :status,
                 display: :badge,
                 value: ->(token, _context) { AdminWebhooksTrafficDefinition.endpoint_token_state(token) },
                 display_options: lambda { |token, _context, value|
                   {
                     text: value.to_s.humanize,
                     style: AdminWebhooksTrafficDefinition.endpoint_token_state_badge_style(token),
                     size: :sm
                   }
                 }
          action :view_endpoint,
                 text: "View endpoint",
                 url: lambda { |token|
                   "/admin/screens/endpoints?#{{
                     provider: token.endpoint&.provider_name,
                     endpoint: token.endpoint&.label
                   }.compact.to_query}"
                 }
          action :revoke,
                 text: "Revoke",
                 url: ->(token) { "/admin/webhooks/endpoints/#{token.endpoint_id}/tokens/#{token.id}" },
                 method: :delete
          default_columns :created_at, :provider, :endpoint, :prefix, :status
          default_sort :created_at, direction: :desc
          paginate per_page: 25, mode: :infinite
        end
      end

      RecordingStudioWebhooks.const_set(:AdminWebhooksTokensScreen, screen_class)
    end

    def ensure_tokens_widget_definition!
      if RecordingStudioWebhooks.const_defined?(:AdminWebhooksTokensWidget, false)
        return RecordingStudioWebhooks.const_get(:AdminWebhooksTokensWidget)
      end

      widget = ::RecordingStudioAdmin::Widget.new("widgets.admin_webhooks.tokens") do
        type :list
        title "Recent tokens"
        description "Most recently issued endpoint tokens in this workspace."
        list_options divider: true, hover: true, compact_preview: :text_summary
        hide_change
        hide_metric
        items do |context|
          AdminWebhooksTrafficDefinition.token_widget_items(context)
        end
        rows do |context|
          AdminWebhooksTrafficDefinition.token_widget_rows(context)
        end
        link_to do |context|
          AdminWebhooksTrafficDefinition.token_widget_link(context)
        end
      end

      RecordingStudioWebhooks.const_set(:AdminWebhooksTokensWidget, widget)
    end
  end
end
