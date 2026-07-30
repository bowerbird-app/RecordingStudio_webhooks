# frozen_string_literal: true

RecordingStudioWebhooks.configure do |config|
  # The dummy app has a deliberately narrow admin rule. Production hosts must
  # supply their own authorization and recording scope.
  config.admin_authorizer = lambda do |context|
    actor_allowed = context.actor&.email == "admin@admin.com"
    selected_root = context.controller.current_root_recording
    selected_root_recordable = context.controller.current_root_recordable
    in_admin_tree = selected_root_recordable.respond_to?(:name) && selected_root_recordable.name == "Studio Workspace"

    actor_allowed && selected_root.present? && in_admin_tree
  end

  config.admin_recording_scope = lambda do |context|
    selected_root = context.controller.current_root_recording
    return RecordingStudio::Recording.none unless selected_root

    RecordingStudio::Recording
      .where(trashed_at: nil)
      .where("id = :root_id OR root_recording_id = :root_id", root_id: selected_root.id)
  end

  # Do not queue demo actions from browser exploration.
  config.dispatcher = ->(_plan_id, _wait_until = nil) { true }

  config.provider_roots = [Rails.root.join("app/webhooks/providers").to_s]
  config.action_roots = [Rails.root.join("app/webhooks/actions").to_s]
  config.automatic_discovery = true
end
