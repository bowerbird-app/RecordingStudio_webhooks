# frozen_string_literal: true

module RecordingStudioWebhooks
  class DispatchActionPlan
    def self.call(...) = new(...).call

    def initialize(plan_id, wait_until: nil)
      @plan_id = plan_id
      @wait_until = wait_until
    end

    def call
      plan = ActionPlan.find_by(id: @plan_id)
      return Result.new(status: 404, code: "action_plan_not_found") unless plan

      at = @wait_until || Time.current
      return Result.new(status: 200, code: "action_plan_not_dispatchable", record: plan) unless plan.queue_for_dispatch!(at: at)

      dispatch_result = Dispatcher.enqueue(plan.id, wait_until: @wait_until)
      raise Error, "dispatcher rejected action plan" if dispatch_result == false

      Result.new(status: 202, code: "action_plan_dispatched", record: plan)
    rescue StandardError
      plan&.schedule_dispatch_retry!
      Result.new(status: 503, code: "action_plan_dispatch_unavailable", record: plan)
    end
  end
end
