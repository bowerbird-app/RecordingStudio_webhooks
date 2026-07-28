# frozen_string_literal: true

module RecordingStudioWebhooks
  class ExecuteActionPlan
    ActionContext = Data.define(:action_plan, :inbound_event, :endpoint, :payload, :provenance)

    def self.call(...) = new(...).call

    def initialize(plan_id)
      @plan_id = plan_id
    end

    def call
      plan = ActionPlan.find_by(id: @plan_id)
      return Result.new(status: 404, code: "action_plan_not_found") unless plan

      claim = plan.claim_execution!
      return Result.new(status: 200, code: claim.to_s, record: plan) unless claim == :claimed

      action = RecordingStudioWebhooks.configuration.actions.fetch(plan.action_name)
      unless action && action.fingerprint == plan.action_snapshot.fetch("fingerprint")
        plan.skip!("action_unavailable")
        dispatch_next_sequential(plan.inbound_event)
        return Result.new(status: 200, code: "action_unavailable", record: plan)
      end

      invoke(action.implementation, context_for(plan))
      plan.succeed!
      dispatch_next_sequential(plan.inbound_event)
      Result.new(status: 200, code: "action_succeeded", record: plan)
    rescue StandardError
      return Result.new(status: 500, code: "action_execution_unavailable") unless plan

      outcome = plan.fail_and_schedule_retry!
      DispatchActionPlan.call(plan.id, wait_until: plan.next_attempt_at) if outcome == :retry
      dispatch_next_sequential(plan.inbound_event) if outcome == :failed
      Result.new(status: outcome == :retry ? 202 : 500, code: outcome == :retry ? "action_retry_scheduled" : "action_failed", record: plan)
    end

    private

    def context_for(plan)
      event = plan.inbound_event
      ActionContext.new(
        plan,
        event,
        event.endpoint,
        ImmutableSnapshot.build(event.payload),
        ImmutableSnapshot.build(event.provenance)
      )
    end

    def invoke(handler, context)
      return handler.call(context) if handler.respond_to?(:call)

      instance = handler.new(context)
      return instance.call(context) if instance.respond_to?(:call)
      return instance.perform(context) if instance.respond_to?(:perform)

      raise ConfigurationError, "action handler is unavailable"
    rescue ArgumentError
      instance = handler.new
      return instance.call(context) if instance.respond_to?(:call)
      return instance.perform(context) if instance.respond_to?(:perform)

      raise ConfigurationError, "action handler is unavailable"
    end

    def dispatch_next_sequential(event)
      next_plan = event.action_plans.order(:execution_position).find do |candidate|
        candidate.sequential? && candidate.status.in?(%w[pending retrying]) && candidate.ready_to_execute?
      end
      DispatchActionPlan.call(next_plan.id) if next_plan
    end
  end
end
