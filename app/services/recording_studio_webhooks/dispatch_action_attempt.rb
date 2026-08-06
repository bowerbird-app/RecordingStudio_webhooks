# frozen_string_literal: true

module RecordingStudioWebhooks
  class DispatchActionAttempt
    def self.call(...) = new(...).call

    def initialize(attempt_id, wait_until: nil)
      @attempt_id = attempt_id
      @wait_until = wait_until
    end

    def call
      attempt = ActionAttempt.find_by(id: @attempt_id)
      return Result.new(status: 404, code: "action_attempt_not_found") unless attempt

      at = @wait_until || Time.current
      unless attempt.queue_for_dispatch!(at: at)
        return Result.new(status: 200, code: "action_attempt_not_dispatchable", record: attempt)
      end

      dispatch_result = Dispatcher.enqueue(attempt.id, wait_until: @wait_until)
      raise Error, "dispatcher rejected action attempt" if dispatch_result == false

      Result.new(status: 202, code: "action_attempt_dispatched", record: attempt)
    rescue StandardError
      attempt&.schedule_dispatch_retry!
      Result.new(status: 503, code: "action_attempt_dispatch_unavailable", record: attempt)
    end
  end
end
