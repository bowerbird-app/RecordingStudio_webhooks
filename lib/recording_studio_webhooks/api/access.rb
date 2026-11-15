# frozen_string_literal: true

module RecordingStudioWebhooks
  module Api
    module Access
      module_function

      ResolverContext = Struct.new(:controller)

      def admin_root_recording
        return accessible_admin_root if accessible_admin_root_configured?

        access_recording_from_admin
      end

      def accessible_admin_root_configured?
        return false unless defined?(RecordingStudioAccessible)
        return false unless RecordingStudioAccessible.respond_to?(:configuration)
        return false unless RecordingStudioAccessible.respond_to?(:admin_root)

        RecordingStudioAccessible.configuration.admin_root_resolver.respond_to?(:call)
      end

      def accessible_admin_root
        RecordingStudioAccessible.admin_root
      rescue StandardError
        nil
      end

      def access_recording_from_admin
        return unless defined?(RecordingStudioAdmin)

        resolver = RecordingStudioAdmin.configuration.access_recording_resolver
        return unless resolver

        resolver.call(ResolverContext.new(nil))
      rescue StandardError
        nil
      end

      def actor_for(context)
        context&.access_grant&.actor
      end

      def can_view?(context)
        authorized_on_admin_root?(context, :view)
      end

      def authorized_on_admin_root?(context, role)
        actor = actor_for(context)
        recording = admin_root_recording
        return false if actor.blank? || recording.blank?
        return false unless defined?(RecordingStudioAccessible)

        RecordingStudioAccessible.authorized?(
          actor: actor,
          recording: recording,
          role: role
        )
      end
    end
  end
end
