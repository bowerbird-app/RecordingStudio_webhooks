# frozen_string_literal: true

# app/models/recording_studio_webhooks/webhook_endpoint_token.rb
module RecordingStudioWebhooks
  # Immutable credential snapshot. The digest is never exposed through
  # snapshots, inspection, logs, or action contexts.
  class WebhookEndpointToken < ApplicationRecord
    self.table_name = "recording_studio_webhook_endpoint_tokens"

    Authentication = Data.define(
      :endpoint_recording,
      :endpoint,
      :endpoint_token_recording,
      :endpoint_token_snapshot
    )

    has_one :recording,
      as: :recordable,
      class_name: "RecordingStudio::Recording",
      dependent: :restrict_with_exception
    has_many :incoming_webhook_logs,
      class_name: "RecordingStudioWebhooks::IncomingWebhookLog",
      foreign_key: :endpoint_token_snapshot_id,
      inverse_of: :endpoint_token_snapshot,
      dependent: :restrict_with_exception

    validates :digest, presence: true, uniqueness: true
    validates :prefix, presence: true, length: { maximum: 32 }
    validates :enabled, inclusion: { in: [true, false] }
    validates :active_at, presence: true
    validate :expires_after_activation
    validate :safe_metadata

    before_update :prevent_snapshot_mutation
    before_destroy :prevent_snapshot_mutation

    scope :active, lambda { |at = Time.current|
      where(enabled: true)
        .where(arel_table[:active_at].lteq(at))
        .where(arel_table[:expires_at].eq(nil).or(arel_table[:expires_at].gt(at)))
    }

    class << self
      # Authentication starts with the digest but succeeds only if the matched
      # snapshot is still the recordable currently pointed to by one stable
      # token Recording, which is a direct child of an endpoint Recording.
      def authenticate(provider_name:, plaintext:, at: Time.current)
        return unless RecordingStudioGateway.available?
        return unless plaintext.respond_to?(:to_str)

        value = plaintext.to_str
        return if value.empty?

        digest = TokenDigest.digest(value)
        token_snapshot = active(at).find_by(digest: digest)
        return unless token_snapshot && TokenDigest.secure_compare(digest, token_snapshot.digest)

        token_recording = RecordingStudioGateway.stable_recording_for(token_snapshot)
        return unless token_recording&.parent_recording
        return unless token_recording.recordable_id == token_snapshot.id

        endpoint_recording = token_recording.parent_recording
        endpoint = endpoint_recording.recordable
        return unless endpoint.is_a?(WebhookEndpoint)
        return unless endpoint.enabled? && endpoint.provider_name == provider_name.to_s.downcase

        Authentication.new(endpoint_recording, endpoint, token_recording, token_snapshot)
      rescue RecordingStudioUnavailableError, NameError
        nil
      end
    end

    def active?(at = Time.current)
      enabled? && active_at <= at && (expires_at.nil? || expires_at > at)
    end

    def snapshot
      ImmutableSnapshot.build(
        id: id,
        prefix: prefix,
        enabled: enabled?,
        active_at: active_at,
        expires_at: expires_at,
        created_at: created_at
      )
    end

    def inspect = "#<#{self.class.name} id=#{id.inspect} prefix=#{prefix.inspect} digest=[FILTERED]>"

    private

    def prevent_snapshot_mutation
      raise ActiveRecord::ReadOnlyRecord, "webhook token snapshots are immutable; use Recording Studio revise"
    end

    def expires_after_activation
      return if expires_at.nil? || active_at.nil? || expires_at > active_at

      errors.add(:expires_at, "must be after active_at")
    end

    def safe_metadata
      errors.add(:metadata, "must be safe JSON without secrets") unless safe_value?(metadata || {})
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
