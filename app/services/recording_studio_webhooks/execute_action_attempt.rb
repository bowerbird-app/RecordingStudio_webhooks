# frozen_string_literal: true

module RecordingStudioWebhooks
  class ExecuteActionAttempt
    ActionContext = Data.define(:action_attempt, :inbound_event, :endpoint, :payload, :provenance)

    def self.call(...) = new(...).call

    def initialize(attempt_id)
      @attempt_id = attempt_id
    end

    def call
      attempt = ActionAttempt.find_by(id: @attempt_id)
      return Result.new(status: 404, code: "action_attempt_not_found") unless attempt

      claim = attempt.claim_execution!
      return Result.new(status: 200, code: claim.to_s, record: attempt) unless claim == :claimed

      action = RecordingStudioWebhooks.configuration.actions.fetch(attempt.action_name)
      unless action && action.fingerprint == attempt.action_snapshot.fetch("fingerprint")
        attempt.skip!("action_unavailable")
        dispatch_next_sequential(attempt.inbound_event)
        return Result.new(status: 200, code: "action_unavailable", record: attempt)
      end

      invoke(action.implementation, context_for(attempt))
      attempt.succeed!
      dispatch_next_sequential(attempt.inbound_event)
      Result.new(status: 200, code: "action_succeeded", record: attempt)
    rescue StandardError
      return Result.new(status: 500, code: "action_execution_unavailable") unless attempt

      outcome = attempt.fail_and_schedule_retry!
      DispatchActionAttempt.call(attempt.id, wait_until: attempt.next_attempt_at) if outcome == :retry
      dispatch_next_sequential(attempt.inbound_event) if outcome == :failed
      Result.new(
        status: outcome == :retry ? 202 : 500,
        code: outcome == :retry ? "action_retry_scheduled" : "action_failed",
        record: attempt
      )
    end

    private

    def context_for(attempt)
      event = attempt.inbound_event
      ActionContext.new(
        attempt,
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
      next_attempt = event.action_attempts.order(:execution_position).find do |candidate|
        candidate.sequential? && candidate.status.in?(%w[pending retrying]) && candidate.ready_to_execute?
      end
      DispatchActionAttempt.call(next_attempt.id) if next_attempt
    end
  end
end
