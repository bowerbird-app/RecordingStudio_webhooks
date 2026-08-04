# frozen_string_literal: true

module RecordingStudioWebhooks
  # Queue payloads contain only an action-attempt UUID. They never receive webhook
  # payloads, credentials, or provider signing material.
  class ExecuteActionAttemptJob
    include Sidekiq::Job

    def perform(action_attempt_id)
      ExecuteActionAttempt.call(action_attempt_id)
    end
  end
end
