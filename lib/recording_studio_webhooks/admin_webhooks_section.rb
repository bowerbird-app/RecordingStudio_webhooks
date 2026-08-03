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

    def action_error_relation(context)
      action_plan_relation(context).where(recording_studio_webhooks_action_plans: { status: "failed" })
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
          provider_url: "/admin/screens/providers?#{ { provider: provider_name }.to_query }"
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

    def provider_widget_link(context)
      "/admin/screens/providers"
    end

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
          href: "/admin/webhooks/endpoints/#{row[:endpoint_id]}",
          trailing: "#{events_count} #{events_count == 1 ? 'event' : 'events'}"
        }
      end
    end

    def endpoint_widget_link(_context)
      "/admin/screens/endpoints"
    end

    def action_widget_rows(context)
      range = trailing_30_day_range(Time.current)
      counts = action_plan_relation(context)
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
            attempts_30d: total,
            action_url: "/admin/screens/action_attempts?#{ { action_name: name }.to_query }"
          }
        end
    end

    def action_widget_items(context)
      action_widget_rows(context).map do |row|
        attempts_count = row[:attempts_30d].to_i
        {
          text: row.fetch(:action_name, "Unknown action"),
          href: row[:action_url],
          trailing: "#{attempts_count} #{attempts_count == 1 ? 'attempt' : 'attempts'}"
        }
      end
    end

    def action_widget_link(_context)
      "/admin/screens/actions"
    end

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

      Endpoint.current
        .joins(:recording_studio_recording)
        .where(recording_studio_recordings: { root_recording_id: root_recording.id })
        .left_joins(inbound_events: :action_plans)
        .group("recording_studio_webhooks_endpoints.provider_name")
        .select(
          <<~SQL.squish
            recording_studio_webhooks_endpoints.provider_name AS provider_name,
            COUNT(DISTINCT recording_studio_webhooks_inbound_events.id) AS events_count,
            COUNT(DISTINCT recording_studio_webhooks_endpoints.id) AS endpoints_count,
            COUNT(DISTINCT CASE
              WHEN recording_studio_webhooks_endpoints.enabled THEN recording_studio_webhooks_endpoints.id
            END) AS enabled_endpoints_count,
            MAX(recording_studio_webhooks_inbound_events.received_at) AS last_event_at
          SQL
        )
    end

    def action_plan_relation(context)
      root_recording = context.root_recording
      return ActionPlan.none unless root_recording

      endpoint_ids = Endpoint.joins(:recording_studio_recording)
                             .where(recording_studio_recordings: { root_recording_id: root_recording.id })
                             .select(:id)

      ActionPlan
        .joins(:inbound_event)
        .where(recording_studio_webhooks_inbound_events: { endpoint_id: endpoint_ids })
        .includes(inbound_event: :endpoint)
    end

    def registered_action_rows
      RecordingStudioWebhooks.configuration.actions.all
    end

    def registered_actions_count_for_provider(provider_name)
      registered_action_rows.count do |action|
        action.provider_name.nil? || action.provider_name == provider_name
      end
    end

    def endpoint_filter_values
      Endpoint.distinct.order(:label).pluck(:label)
    end

    def action_filter_values
      observed_actions = ActionPlan.distinct.order(:action_name).pluck(:action_name)
      [ACTION_FILTER_ALL, *observed_actions]
    end

    def action_row_view_url(action, context)
      relation = ActionPlan.joins(:inbound_event)
      root_recording = context&.root_recording
      if root_recording
        endpoint_ids = Endpoint.joins(:recording_studio_recording)
                               .where(recording_studio_recordings: { root_recording_id: root_recording.id })
                               .select(:id)
        relation = relation.where(recording_studio_webhooks_inbound_events: { endpoint_id: endpoint_ids })
      end

      relation = relation.where(recording_studio_webhooks_action_plans: { action_name: action.name })
      relation = relation.where(recording_studio_webhooks_inbound_events: { provider_name: action.provider_name }) if action.provider_name.present?

      latest_plan = relation.order("recording_studio_webhooks_action_plans.created_at DESC").first
      if latest_plan
        return "/admin/webhooks/actionsc/#{latest_plan.id}"
      end

      params = { action_name: action.name }
      params[:provider] = action.provider_name if action.provider_name.present?
      "/admin/screens/action_attempts?#{params.to_query}"
    end

    def action_status_filter_values
      ActionPlan::STATUSES
    end

    def inbound_event_status_badge_style(status)
      case status.to_s
      when "received", "processed", "accepted", "succeeded"
        :success
      when "queued", "pending", "retry_scheduled", "in_progress"
        :warning
      when "failed", "cancelled", "rejected"
        :danger
      else
        :default
      end
    end

    def action_plan_status_badge_style(status)
      case status.to_s
      when "planned", "accepted", "succeeded"
        :success
      when "retry_scheduled", "queued", "in_progress", "skipped"
        :warning
      when "failed", "cancelled"
        :danger
      else
        :default
      end
    end

    def enabled_status_badge_style(enabled)
      enabled ? :success : :default
    end

    def endpoint_token_state(token)
      return "revoked" if token.revoked_at.present?
      return "expired" if token.expires_at.present? && token.expires_at <= Time.current

      "active"
    end

    def endpoint_token_state_badge_style(token)
      case endpoint_token_state(token)
      when "active"
        :success
      when "expired"
        :warning
      when "revoked"
        :danger
      else
        :default
      end
    end

    def endpoint_token_state_badge_style_for(state)
      case state.to_s
      when "active"
        :success
      when "expired"
        :warning
      when "revoked"
        :danger
      else
        :default
      end
    end

    def token_widget_status_badge(context, state)
      state_text = state.to_s.humanize
      view_context = context.respond_to?(:view_context) ? context.view_context : nil
      return state_text unless view_context

      view_context.render(
        FlatPack::Badge::Component.new(
          text: state_text,
          style: endpoint_token_state_badge_style_for(state),
          size: :sm
        )
      )
    end

    def truncated_endpoint_label(label)
      label.to_s.truncate(ENDPOINT_LABEL_TRUNCATE_LENGTH)
    end

    def endpoint_label_tooltip(label)
      text = label.to_s
      return if text.length <= ENDPOINT_LABEL_TRUNCATE_LENGTH

      text
    end

    def weekly_range(reference_time = Time.current)
      reference_time.beginning_of_week..reference_time.end_of_week
    end

    def previous_weekly_range(reference_time = Time.current)
      prior_reference = reference_time - 1.week
      prior_reference.beginning_of_week..prior_reference.end_of_week
    end

    def trailing_30_day_range(reference_time = Time.current)
      (reference_time - 30.days).beginning_of_day..reference_time.end_of_day
    end

    def previous_trailing_30_day_range(reference_time = Time.current)
      previous_end = (reference_time - 30.days).end_of_day
      previous_start = (reference_time - 60.days).beginning_of_day
      previous_start..previous_end
    end

    def percent_change_label(current_count:, previous_count:)
      return "0%" if current_count.zero? && previous_count.zero?
      return "+100%" if previous_count.zero? && current_count.positive?

      percent_change = ((current_count - previous_count) / previous_count.to_f) * 100
      format("%+.0f%%", percent_change)
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

    def action_plan_date_series(relation, frequency)
      bucket = frequency.to_sym
      expression = case bucket
                   when :hour then "DATE_TRUNC('hour', recording_studio_webhooks_action_plans.created_at)"
                   when :week then "DATE_TRUNC('week', recording_studio_webhooks_action_plans.created_at)"
                   when :month then "DATE_TRUNC('month', recording_studio_webhooks_action_plans.created_at)"
                   else "DATE(recording_studio_webhooks_action_plans.created_at)"
                   end
      grouped = Arel.sql(expression)

      relation.except(:order)
              .group(grouped)
              .order(grouped)
              .count
              .map do |timestamp, count|
        { x: format_bucket(timestamp, bucket), y: count.to_i }
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
               value: ->(event, _context) { AdminWebhooksTrafficDefinition.truncated_endpoint_label(event.endpoint.label) },
               tooltip: ->(event, _context) { AdminWebhooksTrafficDefinition.endpoint_label_tooltip(event.endpoint.label) }
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
          column :endpoints_count,
                 title: "Endpoints",
                 value: lambda { |row, context|
                   context.view_context.link_to(
                     row.endpoints_count.to_i,
                     "/admin/screens/endpoints?#{ { provider: row.provider_name }.to_query }",
                     data: { turbo_frame: "_top" }
                   )
                 }
          column :enabled_endpoints_count, title: "Enabled endpoints"
          column :events_count,
                 title: "Inbound events",
                 value: lambda { |row, context|
                   context.view_context.link_to(
                     row.events_count.to_i,
                     "/admin/screens/webhook_traffic?#{ { provider: row.provider_name }.to_query }",
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
                     "/admin/screens/actions?#{ { provider: row.provider_name }.to_query }",
                     data: { turbo_frame: "_top" }
                   )
                 }
          column :last_event_at,
                 title: "Latest event",
                 value: lambda { |row, _context|
                   row.last_event_at&.in_time_zone&.strftime("%b %-d, %Y %H:%M") || "No recent events"
                 }
          default_columns :provider_name, :endpoints_count, :enabled_endpoints_count, :events_count, :actions_count, :last_event_at
          default_sort :events_count, direction: :desc
          paginate per_page: 25, mode: :infinite
        end
      end

      RecordingStudioWebhooks.const_set(:AdminWebhooksProvidersScreen, screen_class)
    end

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
        filter_presentation :inline

        table do
          title "Endpoints"
          column :endpoint_path,
                 title: "URL",
                 sortable: false,
                 value: lambda { |endpoint, _context|
                   now = Time.current
                   current_token = endpoint.endpoint_tokens
                                           .select { |token| token.revoked_at.nil? && token.active_at <= now && (token.expires_at.nil? || token.expires_at > now) }
                                           .max_by(&:active_at)
                   current_plaintext_token = current_token&.attributes&.fetch("token", nil).to_s.presence
                   current_plaintext_token.present? ? "/webhooks/inbound/#{current_plaintext_token}" : "Active token present; full URL unavailable"
                 }
          column :label,
                 value: ->(endpoint, _context) { AdminWebhooksTrafficDefinition.truncated_endpoint_label(endpoint.label) },
                 tooltip: ->(endpoint, _context) { AdminWebhooksTrafficDefinition.endpoint_label_tooltip(endpoint.label) }
          column :provider_name, title: "Provider"
          column :enabled,
                 title: "Status",
                 display: :badge,
                 value: ->(endpoint, _context) { endpoint.enabled? ? "enabled" : "disabled" },
                 display_options: lambda { |endpoint, _context, value|
                   {
                     text: value.to_s.humanize,
                     style: AdminWebhooksTrafficDefinition.enabled_status_badge_style(endpoint.enabled?),
                     size: :sm
                   }
                 }
             action :view,
               text: "View",
               url: ->(endpoint) { "/admin/webhooks/endpoints/#{endpoint.id}" }
          action :edit,
                 text: "Edit",
                 url: ->(endpoint) { "/admin/webhooks/endpoints/#{endpoint.id}/edit" }
          default_columns :endpoint_path, :label, :provider_name, :enabled
          default_sort :created_at, direction: :desc
          paginate per_page: 25, mode: :infinite
        end
      end

      RecordingStudioWebhooks.const_set(:AdminWebhooksEndpointsScreen, screen_class)
    end

    def ensure_action_attempts_screen_class!
      if RecordingStudioWebhooks.const_defined?(:AdminWebhooksActionAttemptsScreen, false)
        return RecordingStudioWebhooks.const_get(:AdminWebhooksActionAttemptsScreen)
      end

      screen_class = Class.new(::RecordingStudioAdmin::Screen) do
        key "action_attempts"
        icon :chart_bar
        title "Action attempts"
        subtitle "Inspect action execution attempts for webhook plans in the current workspace."
        blast_radius :root

        query { |context| AdminWebhooksTrafficDefinition.action_plan_relation(context) }
        filter :date_range, field: :created_at, default: :last_30_days
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
                   relation.where(recording_studio_webhooks_action_plans: { action_name: selected })
                 end
               }
        filter :status,
               options: -> { AdminWebhooksTrafficDefinition.action_status_filter_values },
               apply: lambda { |relation, value, _context|
                 relation.where(recording_studio_webhooks_action_plans: { status: value })
               }
        filter_presentation :inline

        summary do
          label "Action plans"
          change_good_when do |context|
            %w[failed cancelled].include?(context.filter_value(:status).to_s) ? :down : :up
          end
        end

        chart do
          title "Action attempts"
          type :area
          series do |context|
            [{
              name: "Action plans",
              data: AdminWebhooksTrafficDefinition.action_plan_date_series(
                context.query_result.relation,
                context.filter_value(:group_by) || :day
              )
            }]
          end
        end

        table do
          title "Action plans"
          column :created_at
          column :action_name, title: "Action"
          column :attempts, title: "Attempts"
          column :status,
                 display: :badge,
                 display_options: lambda { |_plan, _context, value|
                   {
                     text: value.to_s.humanize,
                     style: AdminWebhooksTrafficDefinition.action_plan_status_badge_style(value),
                     size: :sm
                   }
                 }
          column :provider,
                 title: "Provider",
                 sortable: false,
                 value: ->(plan, _context) { plan.inbound_event.provider_name }
          column :endpoint,
                 title: "Endpoint",
                 sortable: false,
                 value: ->(plan, _context) { AdminWebhooksTrafficDefinition.truncated_endpoint_label(plan.inbound_event.endpoint.label) },
                 tooltip: ->(plan, _context) { AdminWebhooksTrafficDefinition.endpoint_label_tooltip(plan.inbound_event.endpoint.label) }
          action :view,
                 text: "View",
                 url: lambda { |plan|
                   "/admin/webhooks/actionsc/#{plan.id}"
                 }
          default_columns :created_at, :action_name, :attempts, :status, :provider, :endpoint
          default_sort :created_at, direction: :desc
          paginate per_page: 25, mode: :infinite
        end
      end

      RecordingStudioWebhooks.const_set(:AdminWebhooksActionAttemptsScreen, screen_class)
    end

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
          column :name, title: "Action", sortable: false, value: ->(action, _context) { action.name }
          column :provider_name, title: "Provider", sortable: false,
                                 value: ->(action, _context) { action.provider_name.presence || "Any" }
          column :event_pattern, title: "Event pattern", sortable: false,
                                 value: ->(action, _context) { action.event_pattern.value }
          column :priority, title: "Priority", sortable: false, value: ->(action, _context) { action.priority }
          column :source, title: "Source", sortable: false, value: ->(action, _context) { action.source }
          action :view,
                 text: "View",
                 url: lambda { |action, context|
                   AdminWebhooksTrafficDefinition.action_row_view_url(action, context)
                 }
          default_columns :name, :provider_name, :event_pattern, :priority, :source
          paginate per_page: 25, mode: :infinite
        end
      end

      RecordingStudioWebhooks.const_set(:AdminWebhooksActionsScreen, screen_class)
    end

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
                 value: ->(token, _context) { AdminWebhooksTrafficDefinition.truncated_endpoint_label(token.endpoint&.label.to_s) },
                 tooltip: ->(token, _context) { AdminWebhooksTrafficDefinition.endpoint_label_tooltip(token.endpoint&.label.to_s) }
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
          default_columns :created_at, :provider, :endpoint, :prefix, :status
          default_sort :created_at, direction: :desc
          paginate per_page: 25, mode: :infinite
        end
      end

      RecordingStudioWebhooks.const_set(:AdminWebhooksTokensScreen, screen_class)
    end

    def ensure_widget_definition!
      return if RecordingStudioWebhooks.const_defined?(:AdminWebhooksTrafficWidget, false)

      widget = ::RecordingStudioAdmin::Widget.new("widgets.admin_webhooks.traffic") do
        type :chart
        title "Webhook traffic"
        description "Inbound webhook events over the last 30 days."
        change_good_when :up
        metadata { { period_label: "Last 30 days" } }
        value do |context|
          range = 30.days.ago.beginning_of_day..Time.current.end_of_day
          AdminWebhooksTrafficDefinition.traffic_events(context)
                                        .where(received_at: range)
                                        .count
        end
        change do |context|
          reference_time = Time.current
          relation = AdminWebhooksTrafficDefinition.traffic_events(context)
          current_count = relation.where(received_at: AdminWebhooksTrafficDefinition.trailing_30_day_range(reference_time)).count
          previous_count = relation.where(received_at: AdminWebhooksTrafficDefinition.previous_trailing_30_day_range(reference_time)).count
          AdminWebhooksTrafficDefinition.percent_change_label(current_count: current_count,
                                                              previous_count: previous_count)
        end
        chart_type :area
        series do |context|
          range = 30.days.ago.beginning_of_day..Time.current.end_of_day
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

    def ensure_action_attempts_widget_definition!
      if RecordingStudioWebhooks.const_defined?(:AdminWebhooksActionAttemptsWidget, false)
        return RecordingStudioWebhooks.const_get(:AdminWebhooksActionAttemptsWidget)
      end

      widget = ::RecordingStudioAdmin::Widget.new("widgets.admin_webhooks.action_attempts") do
        type :chart
        title "Action attempts"
        description "Action execution attempts over the last 30 days."
        change_good_when :up
        metadata { { period_label: "Last 30 days" } }
        value do |context|
          range = 30.days.ago.beginning_of_day..Time.current.end_of_day
          AdminWebhooksTrafficDefinition.action_plan_relation(context)
                                        .where(created_at: range)
                                        .count
        end
        change do |context|
          reference_time = Time.current
          relation = AdminWebhooksTrafficDefinition.action_plan_relation(context)
          current_count = relation.where(created_at: AdminWebhooksTrafficDefinition.trailing_30_day_range(reference_time)).count
          previous_count = relation.where(created_at: AdminWebhooksTrafficDefinition.previous_trailing_30_day_range(reference_time)).count
          AdminWebhooksTrafficDefinition.percent_change_label(current_count: current_count,
                                                              previous_count: previous_count)
        end
        chart_type :area
        series do |context|
          range = 30.days.ago.beginning_of_day..Time.current.end_of_day
          relation = AdminWebhooksTrafficDefinition.action_plan_relation(context)
                                                   .where(created_at: range)
          [{ name: "Action plans", data: AdminWebhooksTrafficDefinition.action_plan_date_series(relation, :week) }]
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

    def ensure_action_errors_widget_definition!
      if RecordingStudioWebhooks.const_defined?(:AdminWebhooksActionErrorsWidget, false)
        return RecordingStudioWebhooks.const_get(:AdminWebhooksActionErrorsWidget)
      end

      widget = ::RecordingStudioAdmin::Widget.new("widgets.admin_webhooks.action_errors") do
        type :chart
        title "Action errors"
        description "Failed action attempts over the last 30 days."
        change_good_when :down
        metadata { { period_label: "Last 30 days" } }
        value do |context|
          range = 30.days.ago.beginning_of_day..Time.current.end_of_day
          AdminWebhooksTrafficDefinition.action_error_relation(context)
                                        .where(created_at: range)
                                        .count
        end
        change do |context|
          reference_time = Time.current
          relation = AdminWebhooksTrafficDefinition.action_error_relation(context)
          current_count = relation.where(created_at: AdminWebhooksTrafficDefinition.trailing_30_day_range(reference_time)).count
          previous_count = relation.where(created_at: AdminWebhooksTrafficDefinition.previous_trailing_30_day_range(reference_time)).count
          AdminWebhooksTrafficDefinition.percent_change_label(current_count: current_count,
                                                              previous_count: previous_count)
        end
        chart_type :area
        series do |context|
          range = 30.days.ago.beginning_of_day..Time.current.end_of_day
          relation = AdminWebhooksTrafficDefinition.action_error_relation(context)
                                                   .where(created_at: range)
          [{ name: "Failed action plans",
             data: AdminWebhooksTrafficDefinition.action_plan_date_series(relation, :week) }]
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
        link_to { |_context| "/admin/screens/action_attempts?status=failed" }
      end

      RecordingStudioWebhooks.const_set(:AdminWebhooksActionErrorsWidget, widget)
    end

    def ensure_actions_widget_definition!
      if RecordingStudioWebhooks.const_defined?(:AdminWebhooksActionsWidget, false)
        return RecordingStudioWebhooks.const_get(:AdminWebhooksActionsWidget)
      end

      widget = ::RecordingStudioAdmin::Widget.new("widgets.admin_webhooks.actions") do
        type :list
        title "Most Used Actions"
        description "Most-used actions over the last 30 days."
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

  module AdminWebhooksSectionDefinition
    module_function

    def ensure_section_class!
      return nil unless defined?(::RecordingStudioAdmin::Section)

      AdminWebhooksTrafficDefinition.ensure_definitions!
      AdminWebhooksTrafficDefinition.ensure_provider_widget_definition!
      AdminWebhooksTrafficDefinition.ensure_endpoint_widget_definition!
      AdminWebhooksTrafficDefinition.ensure_actions_widget_definition!
      AdminWebhooksTrafficDefinition.ensure_tokens_widget_definition!
      AdminWebhooksTrafficDefinition.ensure_action_attempts_widget_definition!
      AdminWebhooksTrafficDefinition.ensure_action_errors_widget_definition!
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
           link :tokens,
             text: "Tokens",
             url: ->(context) { context.admin_screen_path("tokens") }
      end

      ensure_section_widget_usages!(section_class)

      RecordingStudioWebhooks.const_set(:AdminWebhooksSection, section_class)
    end

    def section_class_defined?
      RecordingStudioWebhooks.const_defined?(:AdminWebhooksSection, false) &&
        RecordingStudioWebhooks.const_get(:AdminWebhooksSection).is_a?(Class)
    end

    def ensure_section_widget_usages!(section_class)
      existing_usages = section_class.widget_usages
      existing_by_key = existing_usages.each_with_object({}) { |usage, memo| memo[usage.key] = usage }

      desired_defaults = {
        "widgets.admin_webhooks.traffic" => { view_variant: :card,
                                              params: { preset_key: :last_30_days, group_by: :week } },
        "widgets.admin_webhooks.action_attempts" => { view_variant: :card,
                                                      params: { preset_key: :last_30_days, group_by: :week } },
        "widgets.admin_webhooks.action_errors" => { view_variant: :card,
                                                    params: { preset_key: :last_30_days, group_by: :week } },
        "widgets.admin_webhooks.actions" => { view_variant: :card, params: { preset_key: :last_30_days } },
        "widgets.admin_webhooks.tokens" => { view_variant: :card, params: { preset_key: :last_30_days } },
        "widgets.admin_webhooks.providers" => { view_variant: :card, params: { preset_key: :last_30_days } },
        "widgets.admin_webhooks.endpoints" => { view_variant: :card, params: { preset_key: :last_30_days } }
      }
      desired_keys = desired_defaults.keys

      ordered_usages = desired_keys.map do |key|
        existing_by_key[key] || ::RecordingStudioAdmin::WidgetUsage.new(
          key: key,
          view_variant: desired_defaults[key][:view_variant],
          title: nil,
          chart_type: nil,
          chart_options: nil,
          params: desired_defaults[key][:params],
          blast_radius: nil,
          link_to: nil
        )
      end

      remaining_usages = existing_usages.reject { |usage| desired_keys.include?(usage.key) }
      final_usages = ordered_usages + remaining_usages
      return if final_usages == existing_usages

      section_class.instance_variable_set(:@widget_keys_value, final_usages)
    end
  end
end
