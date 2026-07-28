# frozen_string_literal: true

# app/models/recording_studio_webhooks/incoming_webhook_log.rb
module RecordingStudioWebhooks
  class IncomingWebhookLog < ApplicationRecord
    self.table_name = "recording_studio_incoming_webhook_logs"

    STATUSES = %w[accepted planned].freeze

    belongs_to :endpoint_recording,
      class_name: "RecordingStudio::Recording",
      optional: false
    belongs_to :endpoint_token_recording,
      class_name: "RecordingStudio::Recording",
      optional: false
    belongs_to :endpoint_snapshot,
      class_name: "RecordingStudioWebhooks::WebhookEndpoint",
      inverse_of: :incoming_webhook_logs
    belongs_to :endpoint_token_snapshot,
      class_name: "RecordingStudioWebhooks::WebhookEndpointToken",
      inverse_of: :incoming_webhook_logs
    has_many :webhook_action_attempts,
      class_name: "RecordingStudioWebhooks::WebhookActionAttempt",
      dependent: :restrict_with_exception,
      inverse_of: :incoming_webhook_log

    validates :provider_name, format: { with: ProviderDefinition::NAME }
    validates :event_type, :provider_event_id, :payload_digest, :accepted_at, presence: true
    validates :provider_event_id, length: { maximum: 255 }
    validates :provider_event_id, uniqueness: { scope: :endpoint_recording_id }
    validates :execution_mode, inclusion: { in: Policy::EXECUTION_MODES }
    validates :status, inclusion: { in: STATUSES }
    validates :policy_source, :policy_pattern, :policy_fingerprint,
      :provider_definition_source, :provider_definition_fingerprint, presence: true
    validate :redacted_payload_is_safe
    validate :provenance_is_safe
    validate :recording_hierarchy_is_consistent

    def sequential? = execution_mode == "sequential"

    def latest_action_attempts
      webhook_action_attempts
        .order(:sequence, :action_key, attempt_number: :desc)
        .to_a
        .group_by(&:action_key)
        .values
        .map(&:first)
        .sort_by { |attempt| [attempt.sequence, attempt.action_key] }
    end

    def snapshot
      ImmutableSnapshot.build(
        id: id,
        endpoint_recording_id: endpoint_recording_id,
        endpoint_token_recording_id: endpoint_token_recording_id,
        endpoint_snapshot_id: endpoint_snapshot_id,
        endpoint_token_snapshot_id: endpoint_token_snapshot_id,
        provider_name: provider_name,
        event_type: event_type,
        provider_event_id: provider_event_id,
        payload_digest: payload_digest,
        policy_source: policy_source,
        policy_pattern: policy_pattern,
        execution_mode: execution_mode,
        policy_fingerprint: policy_fingerprint,
        provider_definition_source: provider_definition_source,
        provider_definition_fingerprint: provider_definition_fingerprint,
        accepted_at: accepted_at
      )
    end

    private

    def redacted_payload_is_safe
      unless redacted_payload.is_a?(Hash) || redacted_payload.is_a?(Array)
        errors.add(:redacted_payload, "must be JSON")
        return
      end

      return if redacted_payload == Redactor.redact(redacted_payload, keys: RecordingStudioWebhooks.configuration.secret_redaction_keys)

      errors.add(:redacted_payload, "contains an unredacted secret")
    end

    def provenance_is_safe
      unless provenance.is_a?(Hash)
        errors.add(:provenance, "must be a JSON object")
        return
      end

      errors.add(:provenance, "contains a secret") unless safe_value?(provenance)
    end

    def recording_hierarchy_is_consistent
      return if endpoint_recording_id.blank? || endpoint_token_recording_id.blank?
      return unless endpoint_token_recording

      errors.add(:endpoint_token_recording, "must be a direct endpoint child") unless
        endpoint_token_recording.parent_recording_id == endpoint_recording_id
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
