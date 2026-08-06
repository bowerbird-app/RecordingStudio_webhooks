# frozen_string_literal: true

module RecordingStudioWebhooks
  module Admin
    class Registration
      def self.register!
        return unless defined?(::RecordingStudioAdmin)

        section_class = RecordingStudioWebhooks::AdminWebhooksSectionDefinition.ensure_section_class!
        return unless section_class

        traffic_screen, traffic_widget = RecordingStudioWebhooks::AdminWebhooksTrafficDefinition.ensure_definitions!
        endpoints_screen = RecordingStudioWebhooks::AdminWebhooksTrafficDefinition.ensure_endpoints_screen_class!
        providers_screen = RecordingStudioWebhooks::AdminWebhooksTrafficDefinition.ensure_provider_screen_class!
        actions_screen = RecordingStudioWebhooks::AdminWebhooksTrafficDefinition.ensure_actions_screen_class!
        tokens_screen = RecordingStudioWebhooks::AdminWebhooksTrafficDefinition.ensure_tokens_screen_class!
        providers_widget = RecordingStudioWebhooks::AdminWebhooksTrafficDefinition.ensure_provider_widget_definition!
        endpoints_widget = RecordingStudioWebhooks::AdminWebhooksTrafficDefinition.ensure_endpoint_widget_definition!
        actions_widget = RecordingStudioWebhooks::AdminWebhooksTrafficDefinition.ensure_actions_widget_definition!
        tokens_widget = RecordingStudioWebhooks::AdminWebhooksTrafficDefinition.ensure_tokens_widget_definition!
        action_attempts_screen = RecordingStudioWebhooks::AdminWebhooksTrafficDefinition.ensure_action_attempts_screen_class!
        action_attempts_widget = RecordingStudioWebhooks::AdminWebhooksTrafficDefinition.ensure_action_attempts_widget_definition!
        action_errors_widget = RecordingStudioWebhooks::AdminWebhooksTrafficDefinition.ensure_action_errors_widget_definition!

        RecordingStudioAdmin.register_section(section_class)
        RecordingStudioAdmin.register_screen(traffic_screen)
        RecordingStudioAdmin.register_screen(endpoints_screen)
        RecordingStudioAdmin.register_screen(providers_screen)
        RecordingStudioAdmin.register_screen(actions_screen)
        RecordingStudioAdmin.register_screen(tokens_screen)
        RecordingStudioAdmin.register_screen(action_attempts_screen)
        RecordingStudioAdmin.register_widget(traffic_widget)
        RecordingStudioAdmin.register_widget(providers_widget)
        RecordingStudioAdmin.register_widget(endpoints_widget)
        RecordingStudioAdmin.register_widget(actions_widget)
        RecordingStudioAdmin.register_widget(tokens_widget)
        RecordingStudioAdmin.register_widget(action_attempts_widget)
        RecordingStudioAdmin.register_widget(action_errors_widget)
      end
    end
  end
end
