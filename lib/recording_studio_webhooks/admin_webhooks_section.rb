# frozen_string_literal: true

module RecordingStudioWebhooks
  module AdminWebhooksSectionDefinition
    module_function

    def ensure_section_class!
      return nil unless defined?(::RecordingStudioAdmin::Section)
      return RecordingStudioWebhooks::AdminWebhooksSection if section_class_defined?

      section_class = Class.new(::RecordingStudioAdmin::Section) do
        key "admin_webhooks"
        title "Admin Webhooks"
        subtitle "Webhook health, providers, endpoints, activity, failures, policies, and sandbox."

        link :admin_webhooks,
             text: "Open Admin Webhooks",
             url: lambda { |context|
               routes = context.controller.main_app
               if routes.respond_to?(:recording_studio_webhooks)
                 routes.recording_studio_webhooks.admin_root_path
               elsif routes.respond_to?(:recording_studio_webhooks_admin_root_path)
                 routes.recording_studio_webhooks_admin_root_path
               else
                 "/webhooks/admin"
               end
             },
             style: :primary
      end

      RecordingStudioWebhooks.const_set(:AdminWebhooksSection, section_class)
    end

    def section_class_defined?
      RecordingStudioWebhooks.const_defined?(:AdminWebhooksSection, false) &&
        RecordingStudioWebhooks.const_get(:AdminWebhooksSection).is_a?(Class)
    end
  end
end
