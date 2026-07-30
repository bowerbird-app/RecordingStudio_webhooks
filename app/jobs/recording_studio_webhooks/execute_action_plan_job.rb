# frozen_string_literal: true

module RecordingStudioWebhooks
  # Queue payloads contain only an action-plan UUID. They never receive webhook
  # payloads, credentials, or provider signing material.
  class ExecuteActionPlanJob
    include Sidekiq::Job

    def perform(action_plan_id)
      ExecuteActionPlan.call(action_plan_id)
    end
  end
end
