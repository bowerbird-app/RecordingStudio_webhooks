# frozen_string_literal: true

# app/services/recording_studio_webhooks/dispatch_webhook_action_attempt.rb
module RecordingStudioWebhooks
  class DispatchWebhookActionAttempt
    def self.call(...) = new(...).call

    def initialize(attempt_id, wait_until: nil)
      @attempt_id = attempt_id
      @wait_until = wait_until
    end

    def call
      attempt = WebhookActionAttempt.find_by(id: @attempt_id)
      return Result.new(status: 404, code: "action_attempt_not_found") unless attempt
      dispatch_at = @wait_until || Time.current
      return Result.new(status: 200, code: "action_attempt_not_dispatchable", record: attempt) unless attempt.queue_for_dispatch!(at: dispatch_at)

      dispatch_result = Dispatcher.enqueue(attempt.id, wait_until: @wait_until)
      raise Error, "dispatcher rejected action attempt" if dispatch_result == false

      job_id = dispatch_result.respond_to?(:job_id) ? dispatch_result.job_id : dispatch_result
      attempt.mark_dispatched!(backend: backend_name, job_id: job_id)
      Result.new(status: 202, code: "action_attempt_dispatched", record: attempt)
    rescue StandardError
      attempt&.schedule_dispatch_retry!
      Result.new(status: 503, code: "action_attempt_dispatch_unavailable", record: attempt)
    end

    private

    def backend_name
      value = RecordingStudioWebhooks.configuration.dispatcher
      value.is_a?(Symbol) ? value.to_s : "custom"
    end
  end
end
