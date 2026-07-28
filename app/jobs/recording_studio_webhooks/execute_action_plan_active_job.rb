# frozen_string_literal: true

# app/jobs/recording_studio_webhooks/execute_action_plan_active_job.rb
module RecordingStudioWebhooks
  class ExecuteActionPlanActiveJob < ActiveJob::Base
    def perform(action_plan_id)
      ExecuteActionPlan.call(action_plan_id)
    end
  end
end
