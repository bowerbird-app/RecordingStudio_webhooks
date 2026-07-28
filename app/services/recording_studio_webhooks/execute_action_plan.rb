# frozen_string_literal: true

# app/services/recording_studio_webhooks/execute_action_plan.rb
module RecordingStudioWebhooks
  class ExecuteActionPlan
    ActionContext = Struct.new(:action_plan, :inbound_event, :endpoint, :payload, :provenance, keyword_init: true) do
      def initialize(**attributes)
        super(
          action_plan: attributes.fetch(:action_plan),
          inbound_event: attributes.fetch(:inbound_event),
          endpoint: attributes.fetch(:endpoint),
          payload: ImmutableSnapshot.build(attributes.fetch(:payload)),
          provenance: ImmutableSnapshot.build(attributes.fetch(:provenance))
        )
        freeze
      end
    end

    def self.call(...) = new(...).call

    def initialize(action_plan_id)
      @action_plan_id = action_plan_id
    end

    def call
      plan = ActionPlan.find_by(id: @action_plan_id)
      return Result.new(status: 404, code: "action_plan_not_found") unless plan

      claim = plan.claim_execution!
      return Result.new(status: 200, code: claim.to_s, record: plan) unless claim == :claimed

      action = RecordingStudioWebhooks.configuration.actions.fetch(plan.action_name)
      unless action
        plan.skip!
        dispatch_next_sequential(plan)
        return Result.new(status: 200, code: "action_unavailable", record: plan)
      end

      invoke(action.implementation, context_for(plan))
      plan.succeed!
      dispatch_next_sequential(plan)
      Result.new(status: 200, code: "action_succeeded", record: plan)
    rescue StandardError
      return Result.new(status: 500, code: "action_execution_unavailable") unless plan

      outcome = plan.fail_or_retry!
      if outcome == :retry
        DispatchActionPlan.call(plan.id, wait_until: plan.reload.next_attempt_at)
        Result.new(status: 202, code: "action_retry_scheduled", record: plan)
      else
        dispatch_next_sequential(plan) if outcome == :failed
        Result.new(status: 500, code: "action_failed", record: plan)
      end
    end

    private

    def context_for(plan)
      event = plan.inbound_event
      ActionContext.new(
        action_plan: plan,
        inbound_event: event,
        endpoint: event.endpoint,
        payload: event.payload,
        provenance: event.provenance
      )
    end

    def invoke(handler, context)
      return handler.call(context) if handler.respond_to?(:call)

      instance = build_handler(handler, context)
      return instance.call(context) if instance.respond_to?(:call)
      return instance.perform(context) if instance.respond_to?(:perform)

      raise ConfigurationError, "action handler is unavailable"
    end

    def build_handler(handler, context)
      handler.new(context)
    rescue ArgumentError
      handler.new
    end

    def dispatch_next_sequential(plan)
      next_plan = plan.inbound_event.action_plans
        .where("execution_position > ?", plan.execution_position)
        .where("policy_snapshot ->> 'execution_mode' = ?", "sequential")
        .where(status: "pending")
        .order(:execution_position)
        .find(&:ready_to_execute?)
      DispatchActionPlan.call(next_plan.id) if next_plan
    end
  end
end
