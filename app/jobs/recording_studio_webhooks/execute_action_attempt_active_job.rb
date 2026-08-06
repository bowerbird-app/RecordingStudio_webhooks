# frozen_string_literal: true

module RecordingStudioWebhooks
  class ExecuteActionAttemptActiveJob < ActiveJob::Base
    def perform(action_attempt_id)
      ExecuteActionAttempt.call(action_attempt_id)
    end
  end
end
