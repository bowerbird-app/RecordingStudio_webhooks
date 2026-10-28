# frozen_string_literal: true

module RecordingStudioWebhooks
  module AdminWebhooksSectionDefinition
    module_function

    def ensure_section_class!
      return nil unless defined?(::RecordingStudioAdmin::Section)

      AdminWebhooksTrafficDefinition.ensure_definitions!
      AdminWebhooksTrafficDefinition.ensure_provider_widget_definition!
      AdminWebhooksTrafficDefinition.ensure_endpoint_widget_definition!
      AdminWebhooksTrafficDefinition.ensure_actions_widget_definition!
      AdminWebhooksTrafficDefinition.ensure_action_attempts_widget_definition!
      RecordingStudioWebhooks::Admin::MetricWidgets.ensure_failed_widget!
      RecordingStudioWebhooks::Admin::MetricWidgets.ensure_stuck_widget!
      if section_class_defined?
        ensure_section_links!(RecordingStudioWebhooks::AdminWebhooksSection)
        ensure_section_widget_usages!(RecordingStudioWebhooks::AdminWebhooksSection)
        return RecordingStudioWebhooks::AdminWebhooksSection
      end

      section_class = Class.new(::RecordingStudioAdmin::Section) do
        key "admin_webhooks"
        title "Admin Webhooks"
        subtitle "Webhook health, providers, endpoints, activity, failures, policies, and sandbox."
        blast_radius :root
      end

      ensure_section_links!(section_class)
      ensure_section_widget_usages!(section_class)

      RecordingStudioWebhooks.const_set(:AdminWebhooksSection, section_class)
    end

    def section_class_defined?
      RecordingStudioWebhooks.const_defined?(:AdminWebhooksSection, false) &&
        RecordingStudioWebhooks.const_get(:AdminWebhooksSection).is_a?(Class)
    end

    def ensure_section_links!(section_class)
      existing = section_class.links.map(&:name)
      {
        webhook_traffic: "View traffic",
        providers: "Providers",
        endpoints: "Endpoints",
        actions: "Actions",
        action_attempts: "Action attempts",
        tokens: "Tokens"
      }.each do |name, text|
        next if existing.include?(name)

        section_class.link(
          name,
          text: text,
          url: ->(context) { context.admin_screen_path(name.to_s) }
        )
      end
    end

    def ensure_section_widget_usages!(section_class)
      existing_usages = section_class.widget_usages
      existing_by_key = existing_usages.each_with_object({}) { |usage, memo| memo[usage.key] = usage }

      desired_defaults = {
        "widgets.admin_webhooks.traffic" => { view_variant: :card,
                                              params: { preset_key: :last_4_weeks, group_by: :week } },
        "widgets.admin_webhooks.action_attempts" => { view_variant: :card,
                                                      params: { preset_key: :last_4_weeks, group_by: :week } },
        "widgets.admin_webhooks.action_errors" => { view_variant: :card,
                                                    params: { preset_key: :last_4_weeks, group_by: :week } },
        "widgets.admin_webhooks.stuck_retries" => { view_variant: :card },
        "widgets.admin_webhooks.actions" => { view_variant: :card, params: { preset_key: :last_4_weeks } },
        "widgets.admin_webhooks.providers" => { view_variant: :card, params: { preset_key: :last_4_weeks } },
        "widgets.admin_webhooks.endpoints" => { view_variant: :card, params: { preset_key: :last_4_weeks } }
      }
      desired_keys = desired_defaults.keys
      removed_keys = ["widgets.admin_webhooks.tokens", "widgets.admin_webhooks.event_status"]

      ordered_usages = desired_keys.map do |key|
        existing = existing_by_key[key]
        ::RecordingStudioAdmin::WidgetUsage.new(
          key: key,
          view_variant: desired_defaults[key][:view_variant],
          title: existing&.title,
          chart_type: existing&.chart_type,
          chart_options: existing&.chart_options,
          params: desired_defaults[key][:params],
          blast_radius: existing&.blast_radius,
          link_to: existing&.link_to
        )
      end

      remaining_usages = existing_usages.reject do |usage|
        desired_keys.include?(usage.key) || removed_keys.include?(usage.key)
      end
      final_usages = ordered_usages + remaining_usages
      return if final_usages == existing_usages

      section_class.instance_variable_set(:@widget_keys_value, final_usages)
    end
  end
end
