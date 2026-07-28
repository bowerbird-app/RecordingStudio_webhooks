# frozen_string_literal: true

# app/models/recording_studio_webhooks/action_plan.rb
module RecordingStudioWebhooks
  class ActionPlan < ApplicationRecord
    self.table_name = "recording_studio_webhooks_action_plans"

    STATES = %w[pending queued running retry_scheduled succeeded failed skipped].freeze
    TERMINAL_STATES = %w[succeeded failed skipped].freeze

    STATES.each do |state|
      define_method("#{state}?") { status == state }
    end

    belongs_to :inbound_event, class_name: "RecordingStudioWebhooks::InboundEvent", inverse_of: :action_plans

    attr_readonly :inbound_event_id, :action_name, :execution_position,
      :endpoint_snapshot, :token_snapshot, :policy_snapshot, :action_snapshot

    validates :action_name, :execution_position, presence: true
    validates :action_name, uniqueness: { scope: :inbound_event_id }
    validates :execution_position, uniqueness: { scope: :inbound_event_id }
    validates :status, inclusion: { in: STATES }
    validates :attempts, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validate :snapshots_are_hashes
    validate :attempt_history_is_append_only, on: :update

    scope :terminal, -> { where(status: TERMINAL_STATES) }
    scope :nonterminal, -> { where.not(status: TERMINAL_STATES) }

    def terminal? = TERMINAL_STATES.include?(status)

    def policy = Policy.new(policy_snapshot)

    def sequential? = policy.sequential?

    def ready_to_execute?
      return true unless sequential?

      inbound_event.action_plans
        .where("execution_position < ?", execution_position)
        .where("policy_snapshot ->> 'execution_mode' = ?", "sequential")
        .where.not(status: TERMINAL_STATES)
        .none?
    end

    def queue_for_dispatch!
      with_lock do
        return false if terminal? || running? || queued?
        return false unless ready_to_execute?

        update!(status: "queued") if pending?
        true
      end
    end

    def claim_execution!(at: Time.current)
      with_lock do
        return :terminal if terminal?
        return :running if running?
        return :not_ready unless ready_to_execute?
        return :not_due if retry_scheduled? && next_attempt_at && next_attempt_at > at

        self.status = "running"
        self.attempts += 1
        self.started_at ||= at
        self.next_attempt_at = nil
        append_history("started", at: at, attempt: attempts)
        save!
        :claimed
      end
    end

    def succeed!(at: Time.current)
      transition_terminal!("succeeded", at: at)
    end

    def skip!(reason = "action_unavailable", at: Time.current)
      transition_terminal!("skipped", at: at, error: reason)
    end

    def fail_or_retry!(at: Time.current)
      with_lock do
        return :terminal if terminal?

        if attempts <= policy.max_retries
          delay = [policy.retry_backoff * (2**(attempts - 1)), policy.max_retry_backoff].min
          self.status = "retry_scheduled"
          self.next_attempt_at = at + delay
          self.last_error = "action_execution_failed"
          append_history("retry_scheduled", at: at, attempt: attempts, error: last_error, retry_in: delay)
          save!
          :retry
        else
          self.status = "failed"
          self.completed_at = at
          self.last_error = "action_execution_failed"
          append_history("failed", at: at, attempt: attempts, error: last_error)
          save!
          :failed
        end
      end
    end

    # Queue infrastructure can be transiently unavailable. Keep the plan
    # recoverable instead of turning an accepted inbound event into a terminal
    # failure. `recording_studio_webhooks:dispatch_due` reconciles plans after
    # a process crash or a queue outage.
    def schedule_dispatch_retry!(at: Time.current)
      with_lock do
        return false if terminal?

        dispatch_failures = Array(attempt_history).count do |entry|
          entry["state"] == "dispatch_retry_scheduled"
        end
        delay = [
          policy.retry_backoff * (2**[dispatch_failures, 10].min),
          policy.max_retry_backoff
        ].min
        self.status = "retry_scheduled"
        self.next_attempt_at = at + delay
        self.last_error = "dispatch_unavailable"
        append_history(
          "dispatch_retry_scheduled",
          at: at,
          attempt: attempts,
          error: last_error,
          retry_in: delay
        )
        save!
        true
      end
    end
    alias dispatch_failed! schedule_dispatch_retry!

    def recover_stale_queue!(stale_before:, at: Time.current)
      with_lock do
        return false unless queued? && updated_at <= stale_before

        self.status = "pending"
        append_history("queue_recovered", at: at, attempt: attempts)
        save!
        true
      end
    end

    def snapshot
      ImmutableSnapshot.build(
        id: id,
        inbound_event_id: inbound_event_id,
        action_name: action_name,
        execution_position: execution_position,
        status: status,
        attempts: attempts,
        endpoint_snapshot: endpoint_snapshot,
        token_snapshot: token_snapshot,
        policy_snapshot: policy_snapshot,
        action_snapshot: action_snapshot
      )
    end

    private

    def transition_terminal!(target_state, at:, error: nil)
      with_lock do
        return false if terminal?

        self.status = target_state
        self.completed_at = at
        self.last_error = error
        append_history(target_state, at: at, attempt: attempts, error: error)
        save!
        true
      end
    end

    def append_history(state, at:, attempt:, error: nil, retry_in: nil)
      entry = { "state" => state, "at" => at.iso8601(6), "attempt" => attempt }
      entry["error"] = error if error
      entry["retry_in"] = retry_in if retry_in
      self.attempt_history = Array(attempt_history) + [entry]
    end

    def snapshots_are_hashes
      %i[endpoint_snapshot token_snapshot policy_snapshot action_snapshot].each do |attribute|
        errors.add(attribute, "must be a JSON object") unless public_send(attribute).is_a?(Hash)
      end
    end

    def attempt_history_is_append_only
      previous = Array(attempt_history_was)
      current = Array(attempt_history)
      errors.add(:attempt_history, "is append-only") unless current.first(previous.length) == previous
    end
  end
end
