# frozen_string_literal: true

module RecordingStudioWebhooks
  module Admin
    class Registration
      def self.register!
        return unless defined?(::RecordingStudioAdmin)

        section_class = RecordingStudioWebhooks::AdminWebhooksSectionDefinition.ensure_section_class!
        return unless section_class

        traffic_screen, traffic_widget = RecordingStudioWebhooks::AdminWebhooksTrafficDefinition.ensure_definitions!
        providers_screen = RecordingStudioWebhooks::AdminWebhooksTrafficDefinition.ensure_provider_screen_class!
        providers_widget = RecordingStudioWebhooks::AdminWebhooksTrafficDefinition.ensure_provider_widget_definition!
        action_attempts_screen = RecordingStudioWebhooks::AdminWebhooksTrafficDefinition.ensure_action_attempts_screen_class!
        action_attempts_widget = RecordingStudioWebhooks::AdminWebhooksTrafficDefinition.ensure_action_attempts_widget_definition!

        RecordingStudioAdmin.register_section(section_class)
        RecordingStudioAdmin.register_screen(traffic_screen)
        RecordingStudioAdmin.register_screen(providers_screen)
        RecordingStudioAdmin.register_screen(action_attempts_screen)
        RecordingStudioAdmin.register_widget(traffic_widget)
        RecordingStudioAdmin.register_widget(providers_widget)
        RecordingStudioAdmin.register_widget(action_attempts_widget)
      end
    end
  end
end
