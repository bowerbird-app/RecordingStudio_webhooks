# frozen_string_literal: true

module RecordingStudioWebhooks
  module Admin
    class Registration
      def self.register!
        return unless defined?(::RecordingStudioAdmin)
        section_class = RecordingStudioWebhooks::AdminWebhooksSectionDefinition.ensure_section_class!
        return unless section_class

        RecordingStudioAdmin.register_section(section_class)
      end
    end
  end
end
