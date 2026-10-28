# frozen_string_literal: true

module RecordingStudioWebhooks
  module AdminWebhooksTrafficDefinition
    module_function

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

    def action_attempt_status_badge_style(status)
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

    def endpoint_status_switch(endpoint, context)
      view = context.view_context
      return endpoint.enabled? ? "Enabled" : "Disabled" unless view

      return_to = if view.respond_to?(:request) && view.request
                    view.request.fullpath
                  else
                    "/admin/screens/endpoints"
                  end

      view.form_with(url: "/admin/webhooks/endpoints/#{endpoint.id}", method: :patch,
                     data: { turbo_action: "replace" },
                     class: "inline-flex items-center") do
        view.safe_join([
                         view.hidden_field_tag(:auto_save, "1"),
                         view.hidden_field_tag(:return_to, return_to),
                         view.hidden_field_tag("endpoint[enabled]", "0"),
                         view.tag.label(class: "relative inline-flex items-center cursor-pointer") do
                           view.safe_join([
                                            view.tag.input(
                                              type: "checkbox",
                                              name: "endpoint[enabled]",
                                              value: "1",
                                              class: "sr-only peer",
                                              checked: endpoint.enabled?,
                                              onchange: "this.form.requestSubmit()",
                                              aria: { label: "Toggle endpoint status for #{endpoint.label}" }
                                            ),
                                            view.tag.div(
                                              class: "pointer-events-none rounded-full transition-colors duration-200 h-6 w-11 bg-[var(--switch-track-background-color)] peer-checked:bg-[var(--switch-track-checked-background-color)] peer-focus-visible:ring-2 peer-focus-visible:ring-inset peer-focus-visible:ring-[var(--switch-focus-ring-color)] peer-focus-visible:ring-offset-2",
                                              role: "switch",
                                              aria: { checked: endpoint.enabled? }
                                            ),
                                            view.tag.div(
                                              class: "pointer-events-none absolute left-0.5 top-0 rounded-full bg-[var(--switch-thumb-background-color)] shadow-[var(--switch-thumb-shadow)] transition-transform duration-200 translate-y-0.5 w-5 h-5 peer-checked:translate-x-5"
                                            )
                                          ])
                         end
                       ])
      end
    end

    def endpoint_inbound_path(endpoint)
      now = Time.current
      current_token = endpoint.endpoint_tokens
                              .select do |token|
        token.revoked_at.nil? && token.active_at <= now && (token.expires_at.nil? || token.expires_at > now)
      end
                              .max_by(&:active_at)
      current_plaintext_token = current_token&.attributes&.fetch("token", nil).to_s.presence
      current_plaintext_token.present? ? "/webhooks/inbound/#{current_plaintext_token}" : "Active token present; full URL unavailable"
    end

    def endpoint_inbound_url(endpoint, context)
      inbound_path = endpoint_inbound_path(endpoint)
      return nil unless inbound_path.start_with?("/webhooks/inbound/")

      base_url = context.view_context&.request&.base_url.to_s
      return nil if base_url.empty?

      "#{base_url}#{inbound_path}"
    end
  end
end
