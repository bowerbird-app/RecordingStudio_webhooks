# frozen_string_literal: true

module RecordingStudioWebhooks
  class InboundEvent < ApplicationRecord
    STATUSES = %w[accepted planned].freeze
    SNAPSHOT_ATTRIBUTES = %w[endpoint_snapshot token_snapshot policy_snapshot].freeze

    belongs_to :endpoint
    belongs_to :endpoint_token
    has_many :action_attempts, dependent: :restrict_with_exception

    validates :provider_name, format: { with: ProviderDefinition::NAME }
    validates :event_type, :payload_digest, :deduplication_key, :received_at, presence: true
    validates :status, inclusion: { in: STATUSES }
    validates :deduplication_key, uniqueness: { scope: :endpoint_id }
    validate :safe_payload_and_provenance

    before_update :prevent_snapshot_mutation

    def snapshot
      ImmutableSnapshot.build(
        id: id,
        endpoint_id: endpoint_id,
        endpoint_token_id: endpoint_token_id,
        provider_name: provider_name,
        event_type: event_type,
        provider_event_id: provider_event_id,
        payload_digest: payload_digest,
        deduplication_key: deduplication_key,
        endpoint_snapshot: endpoint_snapshot,
        token_snapshot: token_snapshot,
        policy_snapshot: policy_snapshot,
        received_at: received_at
      )
    end

    private

    def prevent_snapshot_mutation
      return unless (SNAPSHOT_ATTRIBUTES + %w[endpoint_id endpoint_token_id provider_name event_type provider_event_id payload_digest deduplication_key payload provenance received_at]).any? do |attribute|
        will_save_change_to_attribute?(attribute)
      end

      raise ActiveRecord::ReadOnlyRecord, "inbound event snapshots are immutable"
    end

    def safe_payload_and_provenance
      errors.add(:payload, "must be redacted JSON") unless safe_payload?(payload)
      errors.add(:provenance, "must be safe JSON") unless safe_value?(provenance)
      SNAPSHOT_ATTRIBUTES.each do |attribute|
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

    def safe_payload?(value)
      case value
      when Hash
        value.all? do |key, item|
          (!Redactor.secret_key?(key) || item == Redactor::FILTERED) && safe_payload?(item)
        end
      when Array then value.all? { |item| safe_payload?(item) }
      when String then value.bytesize <= 2_048 && (!Redactor.secret_location?(value) || value == Redactor::FILTERED)
      when Numeric, TrueClass, FalseClass, NilClass then true
      else false
      end
    end
  end
end
