# frozen_string_literal: true

RecordingStudio.configure do |config|
  # Registered delegated_type recordables (strings or classes)
  required_recordable_types = [
    "Workspace",
    "Folder",
    "Page",
    "AdminRoot",
    "RecordingStudioWebhooks::Endpoint",
    "RecordingStudioWebhooks::EndpointToken"
  ]
  config.recordable_types = (Array(config.recordable_types) + required_recordable_types).uniq
  config.enable_capability :accessible, on: "Workspace"
  config.enable_capability :api_access_point, on: "Workspace"

  # Require each configured ActiveRecord type to call recording_studio_recordable.
  config.require_recordable_declarations = true

  # Shown in the shared default layout title fallback.
  config.app_name = "Webhook Demo" if config.respond_to?(:app_name=)

  # Actor resolver for events when no actor is explicitly supplied
  config.actor = -> { Current.actor }

  # Core 6.5 fails closed without a write authorizer. AccessCreationContext
  # covers RecordingStudio::Access rows only. Every other write needs :edit.
  config.authorize_write = lambda do |actor:, recording:, root_recording:, recordable:, **|
    next false unless actor

    access_write = recordable.is_a?(RecordingStudio::Access) ||
      recording&.recordable.is_a?(RecordingStudio::Access) ||
      recordable.class.name == "RecordingStudio::Access" ||
      recording&.recordable_type == "RecordingStudio::Access"

    if access_write
      next RecordingStudioAccessible::AccessCreationContext.allowed?
    end

    rec = root_recording || recording
    next false unless rec

    write_actor = actor
    if defined?(RecordingStudioApi::ApiClient) && actor.is_a?(RecordingStudioApi::ApiClient)
      manager = Current.actor
      write_actor = manager if manager && !manager.is_a?(RecordingStudioApi::ApiClient)
    elsif recordable.present? && actor.class == recordable.class && actor.id == recordable.id
      write_actor = Current.actor
    end
    next false unless write_actor

    RecordingStudioAccessible.authorized?(actor: write_actor, recording: rec, role: :edit)
  rescue StandardError
    false
  end

  # Emit ActiveSupport::Notifications events
  config.event_notifications_enabled = true

  # Idempotency behavior for log_event!
  config.idempotency_mode = :return_existing # or :raise

  # Recordable duplication strategy for revisions
  config.recordable_dup_strategy = :dup
end
