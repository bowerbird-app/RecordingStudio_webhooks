# frozen_string_literal: true

# app/jobs/recording_studio_webhooks/execute_webhook_action_attempt_job.rb
module RecordingStudioWebhooks
  # Direct Sidekiq payloads set retry: false in Dispatcher. Arguments are an
  # operational attempt UUID only; webhook payloads and credentials never enter
  # the job backend.
  class ExecuteWebhookActionAttemptJob
    def perform(action_attempt_id)
      ExecuteWebhookActionAttempt.call(action_attempt_id)
    end
  end
end
