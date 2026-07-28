# frozen_string_literal: true

# app/jobs/recording_studio_webhooks/execute_action_plan_job.rb
module RecordingStudioWebhooks
  # Sidekiq resolves this constant by name. It intentionally does not include
  # Sidekiq::Job so requiring the engine never requires Sidekiq.
  class ExecuteActionPlanJob
    def perform(action_plan_id)
      ExecuteActionPlan.call(action_plan_id)
    end
  end
end
