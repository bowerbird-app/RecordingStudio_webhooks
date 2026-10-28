# frozen_string_literal: true

module RecordingStudioWebhooks
  module AdminWebhooksTrafficDefinition
    module_function

    def endpoint_activity_counts_30d(endpoint, reference_time = Time.current)
      end_date = reference_time.to_date
      start_date = end_date - 29.days
      counts_by_date = InboundEvent
                       .where(endpoint_id: endpoint.id, received_at: start_date.beginning_of_day..end_date.end_of_day)
                       .group(Arel.sql("DATE(received_at)"))
                       .count

      (start_date..end_date).map { |date| counts_by_date.fetch(date, 0).to_i }
    end

    def endpoint_activity_chart_link(endpoint)
      "/admin/screens/webhook_traffic?#{{ endpoint: endpoint.label }.to_query}"
    end

    def activity_mini_chart(counts:, description:, url:, context:)
      view = context.view_context
      return "-" unless view

      chart = view.render(
        FlatPack::Chart::Component.new(
          type: :line,
          series: [{ name: description, data: counts }],
          card: false,
          height: 56,
          class: "w-full",
          options: {
            chart: { sparkline: { enabled: true }, toolbar: { show: false } },
            markers: { size: 0 },
            tooltip: { enabled: false },
            grid: { show: false },
            xaxis: {
              labels: { show: false },
              axisBorder: { show: false },
              axisTicks: { show: false }
            },
            yaxis: { show: false },
            legend: { show: false },
            dataLabels: { enabled: false }
          }
        )
      )

      content = view.tag.span(
        view.safe_join([
                         chart,
                         view.tag.span(description, class: "sr-only")
                       ]),
        title: description,
        class: "block w-[104px] min-w-[104px]"
      )

      view.link_to(
        url,
        data: { turbo_frame: "_top" },
        class: "inline-flex items-center"
      ) { content }
    end

    def endpoint_activity_mini_chart(endpoint, context)
      counts = endpoint_activity_counts_30d(endpoint)

      activity_mini_chart(
        counts: counts,
        description: "#{counts.sum} events in last 30 days",
        url: endpoint_activity_chart_link(endpoint),
        context: context
      )
    end

    def endpoint_token_state(token)
      return "revoked" if token.revoked_at.present?
      return "expired" if token.expires_at.present? && token.expires_at <= Time.current

      "active"
    end

    def endpoint_token_state_badge_style(token)
      endpoint_token_state_badge_style_for(endpoint_token_state(token))
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
  end
end
