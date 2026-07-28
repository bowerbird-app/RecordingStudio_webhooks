# frozen_string_literal: true

module RecordingStudioWebhooks
  class RecoverActionPlans
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
      ActionPlan.due(now).order(:created_at).limit(batch_size).map do |plan|
        DispatchActionPlan.call(plan.id, wait_until: plan.next_attempt_at)
      end
    end

    private

    attr_reader :now, :batch_size

    def recover_stale_queues
      ActionPlan.where(status: "queued").where(ActionPlan.arel_table[:queued_at].lteq(now - STALE_QUEUE_AFTER))
        .order(:queued_at).limit(batch_size).find_each { |plan| plan.schedule_dispatch_retry!(at: now) }
    end

    def recover_stale_executions
      ActionPlan.where(status: "running").where(ActionPlan.arel_table[:started_at].lteq(now - STALE_RUNNING_AFTER))
        .order(:started_at).limit(batch_size).find_each do |plan|
          plan.fail_and_schedule_retry!(at: now)
        end
    end
  end
end
