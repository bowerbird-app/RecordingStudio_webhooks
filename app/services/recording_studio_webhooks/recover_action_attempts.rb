# frozen_string_literal: true

module RecordingStudioWebhooks
  class RecoverActionAttempts
    DEFAULT_BATCH_SIZE = 100
    STALE_QUEUE_AFTER = 60.seconds
    STALE_RUNNING_AFTER = 15.minutes

    def self.call(...) = new(...).call

    def initialize(now: Time.current, batch_size: DEFAULT_BATCH_SIZE)
      @now = now
      @batch_size = Integer(batch_size)
    end

    def call
      recover_stale_queues
      recover_stale_executions
      ActionAttempt.due(now).order(:created_at).limit(batch_size).map do |attempt|
        DispatchActionAttempt.call(attempt.id, wait_until: attempt.next_attempt_at)
      end
    end

    private

    attr_reader :now, :batch_size

    def recover_stale_queues
      ActionAttempt
        .where(status: "queued")
        .where(ActionAttempt.arel_table[:queued_at].lteq(now - STALE_QUEUE_AFTER))
        .order(:queued_at).limit(batch_size).find_each { |attempt| attempt.schedule_dispatch_retry!(at: now) }
    end

    def recover_stale_executions
      ActionAttempt
        .where(status: "running")
        .where(ActionAttempt.arel_table[:started_at].lteq(now - STALE_RUNNING_AFTER))
        .order(:started_at).limit(batch_size).find_each do |attempt|
          attempt.fail_and_schedule_retry!(at: now)
        end
    end
  end
end
