# frozen_string_literal: true

module RecordingStudioWebhooks
  class ExecuteActionPlanActiveJob < ActiveJob::Base
    def perform(action_plan_id)
      ExecuteActionPlan.call(action_plan_id)
    end
  end
end
