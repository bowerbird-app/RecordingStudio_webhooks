# frozen_string_literal: true

RecordingStudioWebhooks.configure do |config|
  # The dummy app has a deliberately narrow admin rule. Production hosts must
  # supply their own authorization and recording scope.
  config.admin_authorizer = lambda do |context|
    next false unless defined?(::RecordingStudioAccessible)

    actor = context.actor
    next false unless actor

    selected_root = context.controller.current_root_recording
    next false unless selected_root

    required_role = context.permission.to_sym == :admin ? :admin : :view

    ::RecordingStudioAccessible.authorized?(
      actor: actor,
      recording: selected_root,
      role: required_role
    )
  rescue StandardError
    false
  end

  config.admin_recording_scope = lambda do |context|
    selected_root = context.controller.current_root_recording
    return RecordingStudio::Recording.none unless selected_root

    RecordingStudio::Recording
      .where(trashed_at: nil)
      .where("id = :root_id OR root_recording_id = :root_id", root_id: selected_root.id)
  end

  config.dispatcher = :sidekiq

  config.provider_roots = [Rails.root.join("app/webhooks/providers").to_s]
  config.action_roots = [Rails.root.join("app/webhooks/actions").to_s]
  config.automatic_discovery = true
end
