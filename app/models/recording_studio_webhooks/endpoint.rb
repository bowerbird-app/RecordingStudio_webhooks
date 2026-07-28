# frozen_string_literal: true

# app/models/recording_studio_webhooks/endpoint.rb
module RecordingStudioWebhooks
  class Endpoint < ApplicationRecord
    self.table_name = "recording_studio_webhooks_endpoints"

    belongs_to :recording,
      class_name: "RecordingStudio::Recording",
      foreign_key: :recording_studio_recording_id,
      optional: false
    has_many :endpoint_tokens,
      class_name: "RecordingStudioWebhooks::EndpointToken",
      dependent: :restrict_with_exception,
      inverse_of: :endpoint
    has_many :inbound_events,
      class_name: "RecordingStudioWebhooks::InboundEvent",
      dependent: :restrict_with_exception,
      inverse_of: :endpoint

    scope :enabled, -> { where(enabled: true) }

    attr_readonly :recording_studio_recording_id, :provider_name, :identity_key, :identity

    validates :recording_studio_recording_id, :provider_name, :identity_key, presence: true
    validates :provider_name, format: { with: ProviderDefinition::NAME }
    validates :identity_key,
      format: { with: /\A[a-z0-9][a-z0-9_-]{2,127}\z/ },
      length: { maximum: 128 }
    validates :identity_key, uniqueness: { scope: %i[recording_studio_recording_id provider_name] }
    validate :identity_is_safe
    validate :metadata_is_safe
    validate :policy_overrides_are_valid

    before_validation :normalize_identity_key

    def current_token(at = Time.current)
      endpoint_tokens.current(at).order(active_at: :desc).first
    end

    def issue_token!(expires_at: nil, active_at: Time.current, metadata: {})
      EndpointToken.issue!(endpoint: self, expires_at: expires_at, active_at: active_at, metadata: metadata)
    end
    alias rotate_token! issue_token!

    def snapshot
      ImmutableSnapshot.build(
        id: id,
        recording_studio_recording_id: recording_studio_recording_id,
        provider_name: provider_name,
        identity_key: identity_key,
        identity: identity || {},
        enabled: enabled?,
        policy_overrides: policy_overrides || {},
        metadata: metadata || {}
      )
    end

    # A host application may boot before RecordingStudio. The association
    # remains declared, but reading it safely returns nil until it is available.
    def recording
      return nil unless defined?(::RecordingStudio::Recording)

      super
    rescue NameError
      nil
    end

    private

    def normalize_identity_key
      self.identity_key = identity_key.to_s.downcase.strip
    end

    def identity_is_safe
      validate_safe_hash(:identity)
    end

    def metadata_is_safe
      validate_safe_hash(:metadata)
    end

    def policy_overrides_are_valid
      return if Policy.valid_override?(policy_overrides || {})

      errors.add(:policy_overrides, "contains invalid policy settings")
    end

    def validate_safe_hash(attribute)
      value = public_send(attribute) || {}
      raise UnsafeMetadataError unless value.is_a?(Hash) && safe_metadata?(value)
    rescue UnsafeMetadataError
      errors.add(attribute, "must be a JSON object without secrets")
    end

    def safe_metadata?(value)
      case value
      when Hash
        value.all? do |key, item|
          !Redactor.secret_key?(key) && safe_metadata?(item)
        end
      when Array
        value.all? { |item| safe_metadata?(item) }
      when String
        value.bytesize <= 2_048
      when Numeric, TrueClass, FalseClass, NilClass
        true
      else
        false
      end
    end
  end
end
