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

  # Require each configured ActiveRecord type to call recording_studio_recordable.
  config.require_recordable_declarations = true

  # Shown in the shared default layout title fallback.
  config.app_name = "Webhook Demo" if config.respond_to?(:app_name=)

  # Actor resolver for events when no actor is explicitly supplied
  config.actor = -> { Current.actor }

  # Core 6.5 fails closed without a write authorizer. Allow Accessible grant
  # writes, then require :edit on the recording being written.
  config.authorize_write = lambda do |actor:, recording:, root_recording:, **|
    next false unless actor

    rec = root_recording || recording
    next false unless rec
    next true if RecordingStudioAccessible::AccessCreationContext.allowed?

    RecordingStudioAccessible.authorized?(actor: actor, recording: rec, role: :edit)
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
