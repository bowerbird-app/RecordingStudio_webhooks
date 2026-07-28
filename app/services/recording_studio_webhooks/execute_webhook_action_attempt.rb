# frozen_string_literal: true

# app/services/recording_studio_webhooks/execute_webhook_action_attempt.rb
module RecordingStudioWebhooks
  class ExecuteWebhookActionAttempt
    ActionContext = Struct.new(:webhook_action_attempt, :incoming_webhook_log, :endpoint, :payload, :provenance,
      keyword_init: true) do
      def initialize(**attributes)
        super(
          webhook_action_attempt: attributes.fetch(:webhook_action_attempt),
          incoming_webhook_log: attributes.fetch(:incoming_webhook_log),
          endpoint: attributes.fetch(:endpoint),
          payload: ImmutableSnapshot.build(attributes.fetch(:payload)),
          provenance: ImmutableSnapshot.build(attributes.fetch(:provenance))
        )
        freeze
      end
    end

    def self.call(...) = new(...).call

    def initialize(attempt_id)
      @attempt_id = attempt_id
    end

    def call
      attempt = WebhookActionAttempt.find_by(id: @attempt_id)
      return Result.new(status: 404, code: "action_attempt_not_found") unless attempt

      claim = attempt.claim_execution!
      return Result.new(status: 200, code: claim.to_s, record: attempt) unless claim == :claimed

      action = RecordingStudioWebhooks.configuration.actions.fetch(attempt.action_key)
      unless action && action.fingerprint == attempt.action_fingerprint
        attempt.skip!(action ? "action_definition_changed" : "action_unavailable")
        dispatch_next_sequential(attempt.incoming_webhook_log)
        return Result.new(status: 200, code: "action_unavailable", record: attempt)
      end

      invoke(action.implementation, context_for(attempt))
      attempt.succeed!
      dispatch_next_sequential(attempt.incoming_webhook_log)
      Result.new(status: 200, code: "action_succeeded", record: attempt)
    rescue StandardError
      return Result.new(status: 500, code: "action_execution_unavailable") unless attempt

      outcome, retry_attempt = attempt.fail_and_schedule_retry!
      if outcome == :retry
        DispatchWebhookActionAttempt.call(retry_attempt.id, wait_until: retry_attempt.next_attempt_at)
        Result.new(status: 202, code: "action_retry_scheduled", record: retry_attempt)
      else
        dispatch_next_sequential(attempt.incoming_webhook_log) if outcome == :failed
        Result.new(status: 500, code: "action_failed", record: attempt)
      end
    end

    private

    def context_for(attempt)
      log = attempt.incoming_webhook_log
      ActionContext.new(
        webhook_action_attempt: attempt,
        incoming_webhook_log: log,
        endpoint: log.endpoint_snapshot,
        payload: log.redacted_payload,
        provenance: log.provenance
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

    def dispatch_next_sequential(log)
      return unless log.sequential?

      next_attempt = log.latest_action_attempts.find do |candidate|
        candidate.status.in?(%w[pending retrying]) && candidate.ready_to_execute?
      end
      DispatchWebhookActionAttempt.call(next_attempt.id) if next_attempt
    end
  end
end
