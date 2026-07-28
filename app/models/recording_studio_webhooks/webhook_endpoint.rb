# frozen_string_literal: true

# app/models/recording_studio_webhooks/webhook_endpoint.rb
module RecordingStudioWebhooks
  # Immutable recordable snapshot. Its stable identity is the
  # RecordingStudio::Recording whose current recordable points here.
  class WebhookEndpoint < ApplicationRecord
    self.table_name = "recording_studio_webhook_endpoints"

    has_one :recording,
      as: :recordable,
      class_name: "RecordingStudio::Recording",
      dependent: :restrict_with_exception
    has_many :incoming_webhook_logs,
      class_name: "RecordingStudioWebhooks::IncomingWebhookLog",
      foreign_key: :endpoint_snapshot_id,
      inverse_of: :endpoint_snapshot,
      dependent: :restrict_with_exception

    validates :provider_name, presence: true, format: { with: ProviderDefinition::NAME }
    validates :enabled, inclusion: { in: [true, false] }
    validate :safe_json_attributes
    validate :policy_attributes

    before_validation :normalize_policy_attributes
    before_update :prevent_snapshot_mutation
    before_destroy :prevent_snapshot_mutation

    def snapshot
      ImmutableSnapshot.build(
        id: id,
        provider_name: provider_name,
        enabled: enabled?,
        policy_overrides: policy_overrides || {},
        event_policies: event_policies || [],
        metadata: metadata || {},
        created_at: created_at
      )
    end

    private

    def prevent_snapshot_mutation
      raise ActiveRecord::ReadOnlyRecord, "webhook endpoint snapshots are immutable; use Recording Studio revise"
    end

    def safe_json_attributes
      %i[metadata policy_overrides event_policies].each do |attribute|
        value = public_send(attribute)
        unless value.is_a?(Hash) || (attribute == :event_policies && value.is_a?(Array))
          errors.add(attribute, "must be JSON")
          next
        end

        errors.add(attribute, "must not contain secrets") unless safe_value?(value)
      end
    end

    def policy_attributes
      Policy.normalize_override(policy_overrides || {})
      PolicyResolver.normalize_event_policies(event_policies || [])
    rescue InvalidPolicyError
      errors.add(:policy_overrides, "contains invalid policy settings")
    end

    def normalize_policy_attributes
      self.policy_overrides = Policy.normalize_override(policy_overrides || {})
      self.event_policies = PolicyResolver.normalize_event_policies(event_policies || [])
    rescue InvalidPolicyError
      # The validation adds the user-facing error without raising from AR.
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
