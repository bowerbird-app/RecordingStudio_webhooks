# frozen_string_literal: true

module RecordingStudioWebhooks
  class Endpoint < ApplicationRecord
    belongs_to :recording_studio_recording, class_name: "RecordingStudio::Recording"
    has_many :endpoint_tokens, dependent: :restrict_with_exception
    has_many :inbound_events, dependent: :restrict_with_exception

    validates :provider_name, presence: true, format: { with: ProviderDefinition::NAME }
    validates :identity_key, presence: true, format: { with: /\A[a-z0-9][a-z0-9_-]{2,127}\z/ }
    validates :enabled, inclusion: { in: [true, false] }
    validates :identity, :metadata, presence: true
    validates :identity_key, uniqueness: { scope: %i[recording_studio_recording_id provider_name] }
    validate :safe_json_attributes
    validate :valid_policy_overrides

    before_validation :normalize_attributes
    before_update :prevent_identity_mutation

    def issue_token!(expires_at: nil, metadata: {}, active_at: Time.current)
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
        EndpointToken::Issuance.new(endpoint_token: token, plaintext_token: plaintext)
      end
    end

    def snapshot
      ImmutableSnapshot.build(
        id: id,
        recording_studio_recording_id: recording_studio_recording_id,
        provider_name: provider_name,
        identity_key: identity_key,
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
      self.identity_key = identity_key.to_s.downcase
      self.identity ||= {}
      self.metadata ||= {}
      self.policy_overrides = Policy.normalize_override(policy_overrides || {})
    rescue InvalidPolicyError
      # The validator supplies a safe user-facing error.
    end

    def prevent_identity_mutation
      immutable = %w[recording_studio_recording_id provider_name identity_key identity]
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
