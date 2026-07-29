# frozen_string_literal: true

module RecordingStudioWebhooks
  class Endpoint < ApplicationRecord
    recording_studio_recordable label: "Webhook Endpoint", root: false, allowed_parent_types: ["Workspace"] if respond_to?(:recording_studio_recordable)

    belongs_to :recording_studio_recording, class_name: "RecordingStudio::Recording"
    has_many :endpoint_tokens, dependent: :restrict_with_exception
    has_many :inbound_events, dependent: :restrict_with_exception

    scope :current, lambda {
      joins("INNER JOIN recording_studio_recordings rs_recordings ON rs_recordings.id = recording_studio_webhooks_endpoints.recording_studio_recording_id")
        .where("rs_recordings.recordable_type = ?", name)
        .where("rs_recordings.recordable_id = recording_studio_webhooks_endpoints.id")
    }

    validates :provider_name, presence: true, format: { with: ProviderDefinition::NAME }
    validates :label, presence: true, length: { maximum: 255 }
    validates :enabled, inclusion: { in: [true, false] }
    validate :safe_json_attributes
    validate :json_object_attributes
    validate :valid_policy_overrides

    before_validation :normalize_attributes
    before_update :prevent_identity_mutation

    def issue_token!(expires_at: nil, metadata: {}, active_at: Time.current, actor: nil)
      with_lock do
        endpoint_tokens.where(revoked_at: nil).update_all(revoked_at: active_at, updated_at: active_at)
        plaintext = "rswh_#{SecureRandom.urlsafe_base64(32)}"
        token = endpoint_tokens.create!(
          digest: TokenDigest.digest(plaintext),
          prefix: plaintext.first(13),
          active_at: active_at,
          expires_at: expires_at,
          metadata: metadata || {}
        )
        audit!(
          action: "recording_studio_webhooks.endpoint_token.issued",
          actor: actor,
          metadata: { endpoint_token_id: token.id, endpoint_id: id },
          idempotency_key: "recording_studio_webhooks:endpoint-token:#{token.id}"
        )
        EndpointToken::Issuance.new(endpoint_token: token, plaintext_token: plaintext)
      end
    end
    alias rotate_token! issue_token!

    def audit!(action:, actor: nil, metadata: {}, idempotency_key: nil)
      owner = recording_studio_recording
      RecordingStudioGateway.log_event!(
        root_recording: owner.root_recording_or_self,
        recording: owner,
        action: action,
        actor: actor,
        metadata: metadata,
        idempotency_key: idempotency_key
      )
    end

    def snapshot
      ImmutableSnapshot.build(
        id: id,
        recording_studio_recording_id: recording_studio_recording_id,
        label: label,
        provider_name: provider_name,
        identity: identity,
        enabled: enabled?,
        policy_overrides: policy_overrides,
        metadata: metadata,
        created_at: created_at
      )
    end

    private

    def normalize_attributes
      self.provider_name = provider_name.to_s.downcase
      self.label = label.to_s.strip
      self.label = recording_studio_recording_id.to_s if label.blank?
      self.identity ||= {}
      self.metadata ||= {}
      self.policy_overrides = Policy.normalize_override(policy_overrides || {})
    rescue InvalidPolicyError
      # The validator supplies a safe user-facing error.
    end

    def prevent_identity_mutation
      immutable = %w[recording_studio_recording_id provider_name identity]
      return unless immutable.any? { |attribute| will_save_change_to_attribute?(attribute) }

      raise ActiveRecord::ReadOnlyRecord, "endpoint identity and recording linkage are immutable"
    end

    def valid_policy_overrides
      Policy.normalize_override(policy_overrides || {})
    rescue InvalidPolicyError
      errors.add(:policy_overrides, "contains invalid policy settings")
    end

    def safe_json_attributes
      %i[identity metadata].each do |attribute|
        errors.add(attribute, "must be safe JSON without secrets") unless safe_value?(public_send(attribute))
      end
    end

    def json_object_attributes
      %i[identity metadata].each do |attribute|
        errors.add(attribute, "must be a JSON object") unless public_send(attribute).is_a?(Hash)
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
  end
end
