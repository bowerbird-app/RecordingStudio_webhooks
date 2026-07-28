# frozen_string_literal: true

# app/jobs/recording_studio_webhooks/execute_webhook_action_attempt_active_job.rb
module RecordingStudioWebhooks
  class ExecuteWebhookActionAttemptActiveJob < ActiveJob::Base
    def perform(action_attempt_id)
      ExecuteWebhookActionAttempt.call(action_attempt_id)
    end
  end
end
