# frozen_string_literal: true

# app/services/recording_studio_webhooks/recover_webhook_action_attempts.rb
module RecordingStudioWebhooks
  # Reconciles process crashes between persistence and enqueue, stale queued
  # jobs, and stale running work. Hosts should invoke this from their scheduler.
  class RecoverWebhookActionAttempts
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
      due_attempts.each { |attempt| DispatchWebhookActionAttempt.call(attempt.id, wait_until: attempt.next_attempt_at) }
    end

    private

    attr_reader :now, :batch_size

    def recover_stale_queues
      WebhookActionAttempt.where(status: "queued")
        .where(WebhookActionAttempt.arel_table[:queued_at].lteq(now - STALE_QUEUE_AFTER))
        .order(:queued_at)
        .limit(batch_size)
        .find_each { |attempt| attempt.recover_stale_queue!(stale_before: now - STALE_QUEUE_AFTER, at: now) }
    end

    def recover_stale_executions
      WebhookActionAttempt.where(status: "running")
        .where(WebhookActionAttempt.arel_table[:started_at].lteq(now - STALE_RUNNING_AFTER))
        .order(:started_at)
        .limit(batch_size)
        .find_each { |attempt| attempt.recover_stale_execution!(stale_before: now - STALE_RUNNING_AFTER, at: now) }
    end

    def due_attempts
      WebhookActionAttempt.due(now).order(:created_at).limit(batch_size)
    end
  end
end
