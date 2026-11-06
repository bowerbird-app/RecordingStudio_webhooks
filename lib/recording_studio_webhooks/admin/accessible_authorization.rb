# frozen_string_literal: true

module RecordingStudioWebhooks
  module Admin
    module AccessibleAuthorization
      module_function

      def authorized?(context)
        return false unless defined?(::RecordingStudioAccessible)

        actor = context.actor
        recording = current_root_from(context)
        return false unless actor && recording

        check_accessible(actor: actor, recording: recording, role: required_role(context))
      end

      def recordings_for(context)
        root = current_root_from(context) if authorized?(context)
        return empty_scope unless defined?(::RecordingStudio::Recording) && root

        descendant_scope(root)
      rescue StandardError
        empty_scope
      end

      def current_root_from(context)
        controller = context.respond_to?(:controller) ? context.controller : nil
        return unless controller.respond_to?(:current_root_recording, true)

        controller.send(:current_root_recording)
      end

      def required_role(context)
        permission = context.respond_to?(:permission) ? context.permission : :view
        permission.to_sym == :admin ? :admin : :view
      end

      def check_accessible(actor:, recording:, role:)
        ::RecordingStudioAccessible.authorized?(
          actor: actor,
          recording: recording,
          role: role
        )
      rescue StandardError
        false
      end

      def descendant_scope(root)
        ::RecordingStudio::Recording.where(trashed_at: nil).where(
          "id = :root_id OR root_recording_id = :root_id",
          root_id: root.id
        )
      end

      def empty_scope
        return ::RecordingStudio::Recording.none if defined?(::RecordingStudio::Recording)

        []
      end
    end
  end
end
