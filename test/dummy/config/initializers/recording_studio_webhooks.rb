# frozen_string_literal: true

RecordingStudioWebhooks.configure do |config|
  # The dummy app has a deliberately narrow admin rule. Production hosts must
  # supply their own authorization and recording scope.
  config.admin_authorizer = lambda do |context|
    actor = context.actor
    root = context.controller.current_root_recording
    next false unless actor && root

    role = context.permission.to_sym == :admin ? :admin : :view
    RecordingStudioAccessible.authorized?(actor: actor, recording: root, role: role)
  rescue StandardError
    false
  end

  config.admin_recording_scope = lambda do |context|
    root = context.controller.current_root_recording
    next RecordingStudio::Recording.none unless root

    RecordingStudio::Recording.where(trashed_at: nil)
      .where("id = :root_id OR root_recording_id = :root_id", root_id: root.id)
  end

  # Dummy development uses Sidekiq. Tests use a no-op dispatcher so CI (Postgres
  # only, no Redis) can run execute_action without enqueueing.
  config.dispatcher = if Rails.env.test?
    ->(_attempt_id, wait_until: nil) { true }
  else
    :sidekiq
  end

  config.provider_roots = [Rails.root.join("app/webhooks/providers").to_s]
  config.action_roots = [Rails.root.join("app/webhooks/actions").to_s]
  config.automatic_discovery = true
end
