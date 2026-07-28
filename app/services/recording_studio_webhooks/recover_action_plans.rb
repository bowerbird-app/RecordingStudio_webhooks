# frozen_string_literal: true

module RecordingStudioWebhooks
  # Reconciles plans left behind by a process crash between transaction commit
  # and enqueue, or by a temporary dispatcher outage. Schedule this service
  # through the included rake task or the host's scheduler.
  class RecoverActionPlans
    DEFAULT_BATCH_SIZE = 100
    STALE_QUEUE_AFTER = 60

    def self.call(...) = new(...).call

    def initialize(now: Time.current, batch_size: DEFAULT_BATCH_SIZE)
      @now = now
      @batch_size = Integer(batch_size)
    end

    def call
      recover_stale_queues
      due_plans.map { |plan| DispatchActionPlan.call(plan.id) }
    end

    private

    attr_reader :now, :batch_size

    def recover_stale_queues
      ActionPlan.where(status: "queued")
        .where(ActionPlan.arel_table[:updated_at].lteq(now - STALE_QUEUE_AFTER))
        .order(:updated_at)
        .limit(batch_size)
        .find_each do |plan|
          plan.recover_stale_queue!(stale_before: now - STALE_QUEUE_AFTER, at: now)
        end
    end

    def due_plans
      pending = ActionPlan.where(status: "pending")
      retries = ActionPlan.where(status: "retry_scheduled")
        .where(ActionPlan.arel_table[:next_attempt_at].lteq(now))

      pending.or(retries).order(:created_at).limit(batch_size)
    end
  end
end
