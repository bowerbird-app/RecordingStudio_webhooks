# frozen_string_literal: true

RecordingStudioWebhooks.configure do |config|
  # Admin authorization and recording scope default through Accessible on the
  # current root. Dummy does not replace those hooks.

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
