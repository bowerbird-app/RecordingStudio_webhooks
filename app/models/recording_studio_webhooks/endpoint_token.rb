# frozen_string_literal: true

module RecordingStudioWebhooks
  class EndpointToken < ApplicationRecord
    class Issuance
      attr_reader :endpoint_token

      def initialize(endpoint_token:, plaintext_token:)
        @endpoint_token = endpoint_token
        @plaintext_token = plaintext_token
      end

      def plaintext_token
        raise Error, "plaintext token has already been disclosed" unless @plaintext_token

        token = @plaintext_token
        @plaintext_token = nil
        token
      end
      alias token plaintext_token

      def inspect = "#<#{self.class.name} endpoint_token_id=#{endpoint_token.id.inspect} token=[FILTERED]>"
    end

    belongs_to :endpoint
    has_many :inbound_events, dependent: :restrict_with_exception

    validates :digest, presence: true, uniqueness: true
    validates :prefix, presence: true, length: { maximum: 32 }
    validates :active_at, presence: true
    validate :expires_after_activation
    validate :safe_metadata

    before_update :prevent_credential_mutation
    before_destroy :prevent_destroy

    scope :current, lambda { |at = Time.current|
      where(revoked_at: nil)
        .where(arel_table[:active_at].lteq(at))
        .where(arel_table[:expires_at].eq(nil).or(arel_table[:expires_at].gt(at)))
    }

    def self.authenticate(endpoint:, plaintext:, at: Time.current)
      return unless endpoint.is_a?(Endpoint) && plaintext.respond_to?(:to_str)

      digest = TokenDigest.digest(plaintext.to_str)
      token = endpoint.endpoint_tokens.current(at).find_by(digest: digest)
      token if token && TokenDigest.secure_compare(digest, token.digest)
    end

    def current?(at = Time.current)
      revoked_at.nil? && active_at <= at && (expires_at.nil? || expires_at > at)
    end

    def revoke!(at: Time.current, actor: nil)
      with_lock do
        return false unless current?(at)

        update!(revoked_at: at)
        endpoint.audit!(
          action: "recording_studio_webhooks.endpoint_token.revoked",
          actor: actor,
          metadata: { endpoint_token_id: id, endpoint_id: endpoint_id },
          idempotency_key: "recording_studio_webhooks:endpoint-token-revocation:#{id}"
        )
        true
      end
    end

    def snapshot
      ImmutableSnapshot.build(
        id: id,
        endpoint_id: endpoint_id,
        prefix: prefix,
        active_at: active_at,
        expires_at: expires_at,
        revoked_at: revoked_at,
        metadata: metadata,
        created_at: created_at
      )
    end

    def inspect = "#<#{self.class.name} id=#{id.inspect} prefix=#{prefix.inspect} digest=[FILTERED]>"

    private

    def prevent_credential_mutation
      immutable = %w[endpoint_id digest prefix active_at expires_at metadata]
      return unless immutable.any? { |attribute| will_save_change_to_attribute?(attribute) }

      raise ActiveRecord::ReadOnlyRecord, "endpoint tokens are immutable; issue a replacement token"
    end

    def prevent_destroy
      raise ActiveRecord::ReadOnlyRecord, "endpoint tokens are retained as credential history"
    end

    def expires_after_activation
      errors.add(:expires_at, "must be after active_at") if expires_at && active_at && expires_at <= active_at
    end

    def safe_metadata
      errors.add(:metadata, "must be safe JSON without secrets") unless safe_value?(metadata || {})
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
