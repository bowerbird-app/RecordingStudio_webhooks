# frozen_string_literal: true

# app/models/recording_studio_webhooks/inbound_event.rb
module RecordingStudioWebhooks
  class InboundEvent < ApplicationRecord
    self.table_name = "recording_studio_webhooks_inbound_events"

    belongs_to :endpoint, class_name: "RecordingStudioWebhooks::Endpoint", inverse_of: :inbound_events
    belongs_to :endpoint_token, class_name: "RecordingStudioWebhooks::EndpointToken", inverse_of: :inbound_events
    has_many :action_plans,
      class_name: "RecordingStudioWebhooks::ActionPlan",
      dependent: :restrict_with_exception,
      inverse_of: :inbound_event

    attr_readonly :endpoint_id, :endpoint_token_id, :provider_name, :event_type,
      :provider_event_id, :payload_digest, :deduplication_key, :payload, :provenance,
      :endpoint_snapshot, :token_snapshot, :policy_snapshot, :received_at

    validates :provider_name, format: { with: ProviderDefinition::NAME }
    validates :event_type, :payload_digest, :deduplication_key, :received_at, presence: true
    validates :provider_event_id, length: { maximum: 255 }, allow_nil: true
    validates :deduplication_key, uniqueness: { scope: :endpoint_id }
    validates :status, inclusion: { in: %w[accepted planned] }
    validate :payload_is_redacted
    validate :snapshot_values_are_hashes

    def snapshot
      ImmutableSnapshot.build(
        id: id,
        endpoint_id: endpoint_id,
        endpoint_token_id: endpoint_token_id,
        provider_name: provider_name,
        event_type: event_type,
        provider_event_id: provider_event_id,
        payload_digest: payload_digest,
        received_at: received_at,
        endpoint_snapshot: endpoint_snapshot,
        token_snapshot: token_snapshot,
        policy_snapshot: policy_snapshot
      )
    end

    private

    def payload_is_redacted
      keys = Array(policy_snapshot&.fetch("redaction_keys", nil)) +
        RecordingStudioWebhooks.configuration.secret_redaction_keys
      return if payload == Redactor.redact(payload, keys: keys)

      errors.add(:payload, "contains an unredacted secret")
    end

    def snapshot_values_are_hashes
      %i[provenance endpoint_snapshot token_snapshot policy_snapshot].each do |attribute|
        errors.add(attribute, "must be a JSON object") unless public_send(attribute).is_a?(Hash)
      end
    end
  end
end
