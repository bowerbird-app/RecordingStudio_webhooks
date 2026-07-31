# frozen_string_literal: true

module RecordingStudioWebhooks
  module AdminWebhooksTrafficDefinition
    module_function

    FILTERABLE_GROUPINGS = %i[hour day week month].freeze

    def ensure_definitions!
      return unless defined?(::RecordingStudioAdmin::Screen) && defined?(::RecordingStudioAdmin::Widget)

      ensure_screen_class!
      ensure_provider_screen_class!
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
          provider_url: "/admin/webhooks/providers/#{provider_name}"
        }
      end
    end

    def provider_widget_items(context)
      provider_widget_rows(context).map do |row|
        endpoints_count = row[:endpoints].to_i
        {
          text: row.fetch(:provider, "Unknown"),
          href: row[:provider_url],
          trailing: "#{endpoints_count} #{endpoints_count == 1 ? 'endpoint' : 'endpoints'}"
        }
      end
    end

    def provider_widget_link(context)
      "/admin/screens/providers"
    end

    def provider_screen_relation(context)
      root_recording = context.root_recording
      return InboundEvent.none unless root_recording

      endpoint_ids = Endpoint.joins(:recording_studio_recording)
                             .where(recording_studio_recordings: { root_recording_id: root_recording.id })
                             .select(:id)

      InboundEvent
        .where(endpoint_id: endpoint_ids)
        .joins(:endpoint)
        .group("recording_studio_webhooks_inbound_events.provider_name")
        .select(
          <<~SQL.squish
            recording_studio_webhooks_inbound_events.provider_name AS provider_name,
            COUNT(recording_studio_webhooks_inbound_events.id) AS events_count,
            COUNT(DISTINCT recording_studio_webhooks_endpoints.id) AS endpoints_count,
            COUNT(DISTINCT CASE
              WHEN recording_studio_webhooks_endpoints.enabled THEN recording_studio_webhooks_endpoints.id
            END) AS enabled_endpoints_count,
            MAX(recording_studio_webhooks_inbound_events.received_at) AS last_event_at
          SQL
        )
    end

    def endpoint_filter_values
      Endpoint.distinct.order(:label).pluck(:label)
    end

    def date_series(relation, frequency)
      bucket = frequency.to_sym
      expression = case bucket
                   when :hour then "DATE_TRUNC('hour', received_at)"
                   when :week then "DATE_TRUNC('week', received_at)"
                   when :month then "DATE_TRUNC('month', received_at)"
                   else "DATE(received_at)"
                   end
      grouped = Arel.sql(expression)

      relation.except(:order).group(grouped).order(grouped).count.map do |timestamp, count|
        { x: format_bucket(timestamp, bucket), y: count }
      end
    end

    def format_bucket(timestamp, frequency)
      value = timestamp.respond_to?(:in_time_zone) ? timestamp.in_time_zone : Time.zone.parse(timestamp.to_s)

      case frequency
      when :hour then value.strftime("%-l%P").strip
      when :week then "Week of #{value.strftime('%b %-d')}"
      when :month then value.strftime("%b")
      else value.strftime("%b %-d")
      end
    end

    def ensure_screen_class!
      return if RecordingStudioWebhooks.const_defined?(:AdminWebhooksTrafficScreen, false)

      screen_class = Class.new(::RecordingStudioAdmin::Screen) do
        key "webhook_traffic"
        icon :chart_bar
        title "Webhook traffic"
        subtitle "Inspect inbound webhook volume for the current workspace."
        blast_radius :root

        query { |context| AdminWebhooksTrafficDefinition.traffic_events(context) }
        filter :date_range, field: :received_at, default: :last_30_days
        filter :group_by, values: FILTERABLE_GROUPINGS, default: :day
        filter :provider,
               options: -> { AdminWebhooksTrafficDefinition.provider_filter_values },
               apply: ->(relation, value, _context) { relation.where(provider_name: value) }
        filter :endpoint,
               options: -> { AdminWebhooksTrafficDefinition.endpoint_filter_values },
               apply: lambda { |relation, value, _context|
                 relation.joins(:endpoint).where(recording_studio_webhooks_endpoints: { label: value })
               }
        filter_presentation :inline

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
                 value: ->(event, _context) { event.endpoint.label }
          column :event_type, title: "Event type"
          column :status, display: :badge
          action :view,
                 text: "View",
                 url: ->(event) { "/admin/webhooks/endpoints/#{event.endpoint_id}/events/#{event.id}" }
          default_columns :received_at, :provider_name, :endpoint, :event_type, :status
          default_sort :received_at, direction: :desc
          paginate per_page: 25, mode: :infinite
        end
      end

      RecordingStudioWebhooks.const_set(:AdminWebhooksTrafficScreen, screen_class)
    end

    def ensure_provider_screen_class!
      if RecordingStudioWebhooks.const_defined?(:AdminWebhooksProvidersScreen, false)
        return RecordingStudioWebhooks.const_get(:AdminWebhooksProvidersScreen)
      end

      screen_class = Class.new(::RecordingStudioAdmin::Screen) do
        key "providers"
        title "Providers"
        subtitle "Provider performance across webhook endpoints and inbound traffic."
        blast_radius :root

        query { |context| AdminWebhooksTrafficDefinition.provider_screen_relation(context) }
        filter :endpoint,
               options: -> { AdminWebhooksTrafficDefinition.endpoint_filter_values },
               apply: lambda { |relation, value, _context|
                 relation.where(recording_studio_webhooks_endpoints: { label: value })
               }
        filter_presentation :inline

        table do
          title "Provider performance"
          filter :search,
                 apply: lambda { |relation, value, _context|
                   next relation unless value.present?

                   relation.where(
                     "recording_studio_webhooks_inbound_events.provider_name ILIKE :q",
                     q: "%#{ActiveRecord::Base.sanitize_sql_like(value)}%"
                   )
                 }
          column :provider_name, title: "Provider"
          column :endpoints_count, title: "Endpoints"
          column :enabled_endpoints_count, title: "Enabled endpoints"
          column :events_count, title: "Inbound events"
          column :last_event_at,
                 title: "Latest event",
                 value: lambda { |row, _context|
                   row.last_event_at&.in_time_zone&.strftime("%b %-d, %Y %H:%M") || "No recent events"
                 }
          action :view_provider,
                 text: "View provider",
                 url: ->(row) { "/admin/webhooks/providers/#{row.provider_name}" }
          default_columns :provider_name, :endpoints_count, :enabled_endpoints_count, :events_count, :last_event_at
          default_sort :events_count, direction: :desc
          paginate per_page: 25, mode: :infinite
        end
      end

      RecordingStudioWebhooks.const_set(:AdminWebhooksProvidersScreen, screen_class)
    end

    def ensure_widget_definition!
      return if RecordingStudioWebhooks.const_defined?(:AdminWebhooksTrafficWidget, false)

      widget = ::RecordingStudioAdmin::Widget.new("widgets.admin_webhooks.traffic") do
        type :chart
        title "Webhook traffic"
        description "Inbound webhook events over the last 30 days."
        hide_change
        metadata { { period_label: "Last 30 days" } }
        value do |context|
          AdminWebhooksTrafficDefinition.traffic_events(context).where(received_at: 30.days.ago..Time.current).count
        end
        chart_type :area
        series do |context|
          relation = AdminWebhooksTrafficDefinition.traffic_events(context)
                                                   .where(received_at: 30.days.ago..Time.current)
          [{ name: "Inbound events", data: AdminWebhooksTrafficDefinition.date_series(relation, :day) }]
        end
        chart_options { { height: 220 } }
        link_to { |context| context.admin_screen_path("webhook_traffic") }
      end

      RecordingStudioWebhooks.const_set(:AdminWebhooksTrafficWidget, widget)
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

  module AdminWebhooksSectionDefinition
    module_function

    def ensure_section_class!
      return nil unless defined?(::RecordingStudioAdmin::Section)

      AdminWebhooksTrafficDefinition.ensure_definitions!
      AdminWebhooksTrafficDefinition.ensure_provider_widget_definition!
      if section_class_defined?
        ensure_section_widget_usages!(RecordingStudioWebhooks::AdminWebhooksSection)
        return RecordingStudioWebhooks::AdminWebhooksSection
      end

      section_class = Class.new(::RecordingStudioAdmin::Section) do
        key "admin_webhooks"
        title "Admin Webhooks"
        subtitle "Webhook health, providers, endpoints, activity, failures, policies, and sandbox."
        blast_radius :root
        link :webhook_traffic,
             text: "View traffic",
             url: ->(context) { context.admin_screen_path("webhook_traffic") }
      end

      ensure_section_widget_usages!(section_class)

      RecordingStudioWebhooks.const_set(:AdminWebhooksSection, section_class)
    end

    def section_class_defined?
      RecordingStudioWebhooks.const_defined?(:AdminWebhooksSection, false) &&
        RecordingStudioWebhooks.const_get(:AdminWebhooksSection).is_a?(Class)
    end

    def ensure_section_widget_usages!(section_class)
      existing_widget_keys = section_class.widget_usages.map(&:key)

      unless existing_widget_keys.include?("widgets.admin_webhooks.traffic")
        section_class.widget "widgets.admin_webhooks.traffic",
                             view_variant: :card,
                             params: { preset_key: :last_30_days, group_by: :day }
      end

      return if existing_widget_keys.include?("widgets.admin_webhooks.providers")

      section_class.widget "widgets.admin_webhooks.providers",
                           view_variant: :card,
                           params: { preset_key: :last_30_days }
    end
  end
end
