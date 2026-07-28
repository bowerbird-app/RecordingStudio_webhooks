# frozen_string_literal: true

RecordingStudioWebhooks.configure do |config|
  # The dummy app has a deliberately narrow admin rule. Production hosts must
  # supply their own authorization and recording scope.
  config.admin_authorizer = ->(context) { context.actor&.email == "admin@admin.com" }
  config.admin_recording_scope = ->(_context) { RecordingStudio::Recording.where(trashed_at: nil) }

  # Do not queue demo actions from browser exploration.
  config.dispatcher = ->(_plan_id, _wait_until = nil) { true }

  config.provider "demo",
    event_type_extractor: ->(payload) { payload["type"] },
    event_id_extractor: ->(payload) { payload["id"] }

  config.action "demo.received",
    ->(_context) { true },
    provider: "demo",
    event: "demo.received",
    policy: { max_retries: 0, redaction_keys: ["action_only"] }
end
