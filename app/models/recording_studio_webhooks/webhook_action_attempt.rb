# frozen_string_literal: true

# app/models/recording_studio_webhooks/webhook_action_attempt.rb
module RecordingStudioWebhooks
  class WebhookActionAttempt < ApplicationRecord
    self.table_name = "recording_studio_webhook_action_attempts"

    STATUSES = %w[pending queued running retrying succeeded failed skipped cancelled].freeze
    TERMINAL_STATUSES = %w[succeeded failed skipped cancelled].freeze

    belongs_to :incoming_webhook_log,
      class_name: "RecordingStudioWebhooks::IncomingWebhookLog",
      inverse_of: :webhook_action_attempts
    belongs_to :manual_actor, polymorphic: true, optional: true

    STATUSES.each { |state| define_method("#{state}?") { status == state } }

    validates :action_key, :sequence, :attempt_number, :matching_fingerprint,
      :action_source, :action_fingerprint, :policy_source, :policy_pattern,
      :execution_mode, :policy_fingerprint, presence: true
    validates :action_key, length: { maximum: 255 }
    validates :sequence, :attempt_number, :dispatch_failures,
      numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validates :attempt_number, numericality: { greater_than: 0 }
    validates :max_retries, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 20 }
    validates :retry_backoff, :max_retry_backoff,
      numericality: { only_integer: true, greater_than: 0 }
    validates :status, inclusion: { in: STATUSES }
    validates :execution_mode, inclusion: { in: Policy::EXECUTION_MODES }
    validates :attempt_number, uniqueness: { scope: %i[incoming_webhook_log_id action_key] }
    validate :matching_provenance_is_safe

    scope :terminal, -> { where(status: TERMINAL_STATUSES) }
    scope :active, -> { where.not(status: TERMINAL_STATUSES) }
    scope :due, lambda { |at = Time.current|
      where(status: %w[pending retrying])
        .where(arel_table[:next_attempt_at].eq(nil).or(arel_table[:next_attempt_at].lteq(at)))
    }

    def terminal? = TERMINAL_STATUSES.include?(status)

    def latest_for_action?
      incoming_webhook_log.webhook_action_attempts
        .where(action_key: action_key)
        .where("attempt_number > ?", attempt_number)
        .none?
    end

    def ready_to_execute?
      return true unless incoming_webhook_log.sequential?

      incoming_webhook_log.webhook_action_attempts
        .where("sequence < ?", sequence)
        .where.not(status: TERMINAL_STATUSES)
        .none?
    end

    def queue_for_dispatch!(at: Time.current)
      with_lock do
        return false unless latest_for_action? && !terminal? && !running? && !queued?
        return false unless ready_to_execute?
        return false if retrying? && next_attempt_at && next_attempt_at > at

        update!(status: "queued", queued_at: at, next_attempt_at: nil)
        true
      end
    end

    def mark_dispatched!(backend:, job_id:, at: Time.current)
      with_lock do
        return false unless queued?

        update!(
          backend: backend.to_s.byteslice(0, 64),
          job_id: job_id.to_s.byteslice(0, 255).presence,
          queued_at: queued_at || at
        )
        true
      end
    end

    def claim_execution!(at: Time.current)
      with_lock do
        return :terminal unless latest_for_action? && !terminal?
        return :running if running?
        return :not_ready unless ready_to_execute?
        return :not_due if retrying? && next_attempt_at && next_attempt_at > at
        return :not_queued unless queued? || pending? || retrying?

        update!(status: "running", started_at: at, next_attempt_at: nil)
        :claimed
      end
    end

    def succeed!(at: Time.current)
      transition_terminal!("succeeded", at: at)
    end

    def skip!(reason = "action_unavailable", at: Time.current)
      transition_terminal!("skipped", at: at, error: reason)
    end

    def cancel!(reason = "cancelled", at: Time.current)
      transition_terminal!("cancelled", at: at, error: reason)
    end

    # Completes this physical attempt and creates a separate retry row. No
    # mutable JSON attempt history is used; each execution is queryable.
    def fail_and_schedule_retry!(at: Time.current, error: "action_execution_failed")
      with_lock do
        return [:terminal, nil] if terminal?
        return [:not_latest, nil] unless latest_for_action?

        sanitized = sanitize_error(error)
        update!(status: "failed", completed_at: at, last_error: sanitized)
        return [:failed, nil] if attempt_number > max_retries

        delay = [retry_backoff * (2**(attempt_number - 1)), max_retry_backoff].min
        retry_attempt = self.class.create!(retry_attributes(at: at, delay: delay))
        [:retry, retry_attempt]
      end
    end

    def schedule_dispatch_retry!(at: Time.current)
      with_lock do
        return false if terminal? || running?

        failures = dispatch_failures + 1
        if failures > max_retries
          update!(
            status: "cancelled",
            dispatch_failures: failures,
            completed_at: at,
            last_error: "dispatch_unavailable"
          )
          return false
        end

        delay = [retry_backoff * (2**(failures - 1)), max_retry_backoff].min
        update!(
          status: "retrying",
          dispatch_failures: failures,
          next_attempt_at: at + delay,
          last_error: "dispatch_unavailable"
        )
        true
      end
    end

    def recover_stale_queue!(stale_before:, at: Time.current)
      with_lock do
        return false unless queued? && queued_at && queued_at <= stale_before

        update!(status: "retrying", next_attempt_at: at, last_error: "queue_recovered")
        true
      end
    end

    def recover_stale_execution!(stale_before:, at: Time.current)
      with_lock do
        return false unless running? && started_at && started_at <= stale_before

        schedule_retry_from_stale_execution!(at)
        true
      end
    end

    private

    def transition_terminal!(target, at:, error: nil)
      with_lock do
        return false if terminal?

        update!(status: target, completed_at: at, last_error: error && sanitize_error(error))
        true
      end
    end

    def retry_attributes(at:, delay:)
      {
        incoming_webhook_log: incoming_webhook_log,
        action_key: action_key,
        sequence: sequence,
        attempt_number: attempt_number + 1,
        status: "retrying",
        matching_provenance: matching_provenance,
        matching_fingerprint: matching_fingerprint,
        action_source: action_source,
        action_fingerprint: action_fingerprint,
        policy_source: policy_source,
        policy_pattern: policy_pattern,
        execution_mode: execution_mode,
        policy_fingerprint: policy_fingerprint,
        max_retries: max_retries,
        retry_backoff: retry_backoff,
        max_retry_backoff: max_retry_backoff,
        next_attempt_at: at + delay
      }
    end

    def schedule_retry_from_stale_execution!(at)
      update!(status: "failed", completed_at: at, last_error: "execution_recovered")
      return if attempt_number > max_retries

      delay = [retry_backoff * (2**(attempt_number - 1)), max_retry_backoff].min
      self.class.create!(retry_attributes(at: at, delay: delay))
    end

    def sanitize_error(value)
      value.to_s.gsub(/[\r\n\t]+/, " ").byteslice(0, 1_024).presence || "action_execution_failed"
    end

    def matching_provenance_is_safe
      errors.add(:matching_provenance, "must be a safe JSON object") unless safe_value?(matching_provenance)
    end

    def safe_value?(value)
      case value
      when Hash
        value.all? { |key, item| !Redactor.secret_key?(key) && safe_value?(item) }
      when Array
        value.all? { |item| safe_value?(item) }
      when String
        value.bytesize <= 2_048 && !Redactor.secret_location?(value)
      when Numeric, TrueClass, FalseClass, NilClass
        true
      else
        false
      end
    end
  end
end
