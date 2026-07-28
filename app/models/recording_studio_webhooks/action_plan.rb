# frozen_string_literal: true

module RecordingStudioWebhooks
  class ActionPlan < ApplicationRecord
    STATUSES = %w[pending queued running retrying succeeded failed skipped cancelled].freeze
    TERMINAL_STATUSES = %w[succeeded failed skipped cancelled].freeze
    SNAPSHOT_ATTRIBUTES = %w[endpoint_snapshot token_snapshot policy_snapshot action_snapshot].freeze

    belongs_to :inbound_event

    validates :action_name, :execution_position, presence: true
    validates :execution_position, uniqueness: { scope: :inbound_event_id }
    validates :action_name, uniqueness: { scope: :inbound_event_id }
    validates :status, inclusion: { in: STATUSES }
    validates :attempts, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validate :safe_snapshots

    before_update :prevent_snapshot_mutation
    before_update :ensure_attempt_history_is_append_only

    scope :due, lambda { |at = Time.current|
      where(status: %w[pending retrying])
        .where(arel_table[:next_attempt_at].eq(nil).or(arel_table[:next_attempt_at].lteq(at)))
    }

    def terminal? = TERMINAL_STATUSES.include?(status)
    def policy = Policy.new(policy_snapshot.fetch("values", policy_snapshot))
    def sequential? = policy.sequential?

    def ready_to_execute?
      return true unless sequential?

      inbound_event.action_plans.where("execution_position < ?", execution_position).to_a.none? do |plan|
        plan.sequential? && !plan.terminal?
      end
    end

    def queue_for_dispatch!(at: Time.current)
      with_lock do
        return false if terminal? || running? || queued? || !ready_to_execute?
        return false if retrying? && next_attempt_at && next_attempt_at > at

        transition!("queued", at: at, queued_at: at, next_attempt_at: nil)
      end
    end

    def claim_execution!(at: Time.current)
      with_lock do
        return :terminal if terminal?
        return :running if running?
        return :not_ready unless ready_to_execute?
        return :not_due if retrying? && next_attempt_at && next_attempt_at > at
        return :not_queued unless pending? || queued? || retrying?

        transition!("running", at: at, started_at: at, attempts: attempts + 1, next_attempt_at: nil)
        :claimed
      end
    end

    def succeed!(at: Time.current) = transition!("succeeded", at: at, completed_at: at, last_error: nil)
    def skip!(reason, at: Time.current) = transition!("skipped", at: at, completed_at: at, last_error: sanitized_error(reason))

    def fail_and_schedule_retry!(at: Time.current)
      with_lock do
        return :terminal if terminal?

        if attempts > policy.max_retries
          transition!("failed", at: at, completed_at: at, last_error: "action_execution_failed")
          :failed
        else
          delay = [policy.retry_backoff * (2**(attempts - 1)), policy.max_retry_backoff].min
          transition!("retrying", at: at, next_attempt_at: at + delay, last_error: "action_execution_failed")
          :retry
        end
      end
    end

    def schedule_dispatch_retry!(at: Time.current)
      with_lock do
        return false if terminal?

        delay = [policy.retry_backoff * (2**[attempts, 0].max), policy.max_retry_backoff].min
        transition!("retrying", at: at, next_attempt_at: at + delay, last_error: "dispatch_unavailable")
      end
    end

    STATUSES.each { |state| define_method("#{state}?") { status == state } }

    private

    def transition!(next_status, at:, **attributes)
      return false if terminal?

      history = Array(attempt_history).dup
      history << {
        "status" => next_status,
        "at" => at.iso8601,
        "attempt" => attributes.fetch(:attempts, attempts),
        "error" => attributes[:last_error]
      }.compact
      update!(attributes.merge(status: next_status, attempt_history: history))
      true
    end

    def prevent_snapshot_mutation
      immutable = SNAPSHOT_ATTRIBUTES + %w[inbound_event_id action_name execution_position]
      return unless immutable.any? { |attribute| will_save_change_to_attribute?(attribute) }

      raise ActiveRecord::ReadOnlyRecord, "action plan identity and snapshots are immutable"
    end

    def ensure_attempt_history_is_append_only
      return unless will_save_change_to_attempt_history?

      previous, current = attempt_history_change_to_be_saved
      return if Array(current).first(Array(previous).length) == Array(previous)

      raise ActiveRecord::ReadOnlyRecord, "action plan attempt history is append-only"
    end

    def safe_snapshots
      (SNAPSHOT_ATTRIBUTES + %w[attempt_history]).each do |attribute|
        errors.add(attribute, "must be safe JSON") unless safe_value?(public_send(attribute))
      end
    end

    def safe_value?(value)
      case value
      when Hash then value.all? { |key, item| !Redactor.secret_key?(key) && safe_value?(item) }
      when Array then value.all? { |item| safe_value?(item) }
      when String then value.bytesize <= 2_048 && !Redactor.secret_location?(value)
      when Numeric, TrueClass, FalseClass, NilClass then true
      else false
      end
    end

    def sanitized_error(value)
      value.to_s.gsub(/[\r\n\t]+/, " ").byteslice(0, 1_024).presence || "action_execution_failed"
    end
  end
end
