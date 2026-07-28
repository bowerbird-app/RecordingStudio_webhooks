# frozen_string_literal: true

# app/models/recording_studio_webhooks/endpoint_token.rb
module RecordingStudioWebhooks
  class EndpointToken < ApplicationRecord
    self.table_name = "recording_studio_webhooks_endpoint_tokens"

    belongs_to :endpoint, class_name: "RecordingStudioWebhooks::Endpoint", inverse_of: :endpoint_tokens
    has_many :inbound_events,
      class_name: "RecordingStudioWebhooks::InboundEvent",
      dependent: :restrict_with_exception,
      inverse_of: :endpoint_token

    attr_readonly :endpoint_id, :digest, :prefix, :active_at, :expires_at, :metadata

    validates :digest, presence: true, uniqueness: true
    validates :prefix, presence: true, length: { maximum: 32 }
    validates :active_at, presence: true
    validate :expires_after_activation
    validate :metadata_is_safe

    scope :current, lambda { |at = Time.current|
      where(revoked_at: nil)
        .where(arel_table[:active_at].lteq(at))
        .where(arel_table[:expires_at].eq(nil).or(arel_table[:expires_at].gt(at)))
    }

    class Issuance
      attr_reader :endpoint_token

      def initialize(endpoint_token, plaintext_token)
        @endpoint_token = endpoint_token
        @plaintext_token = plaintext_token
      end

      # This is the sole plaintext exposure. It is deliberately absent from
      # serialization and inspect output and is never retained by the model.
      def plaintext_token
        raise Error, "plaintext token has already been disclosed" unless @plaintext_token

        token = @plaintext_token
        @plaintext_token = nil
        token
      end
      alias token plaintext_token

      def to_h
        ImmutableSnapshot.build(endpoint_token_id: endpoint_token.id, prefix: endpoint_token.prefix)
      end

      def inspect = "#<#{self.class.name} endpoint_token_id=#{endpoint_token.id.inspect} token=[FILTERED]>"
    end

    class << self
      def issue!(endpoint:, expires_at: nil, active_at: Time.current, metadata: {})
        raise ArgumentError, "endpoint must be persisted" unless endpoint.persisted?

        plaintext = "rswh_#{SecureRandom.urlsafe_base64(32)}"
        now = Time.current
        token = nil

        endpoint.with_lock do
          endpoint.endpoint_tokens.where(revoked_at: nil).update_all(revoked_at: now, updated_at: now)
          token = endpoint.endpoint_tokens.create!(
            digest: TokenDigest.digest(plaintext),
            prefix: plaintext.first(13),
            active_at: active_at,
            expires_at: expires_at,
            metadata: metadata
          )
        end

        Issuance.new(token, plaintext)
      end

      def authenticate(endpoint:, plaintext:, at: Time.current)
        return nil unless plaintext.respond_to?(:to_str)

        candidate = plaintext.to_str
        return nil if candidate.empty?

        digest = TokenDigest.digest(candidate)
        token = current(at).find_by(endpoint_id: endpoint.id, digest: digest)
        return nil unless token && TokenDigest.secure_compare(digest, token.digest)

        token
      end
    end

    def current?(at = Time.current)
      revoked_at.nil? && active_at <= at && (expires_at.nil? || expires_at > at)
    end

    def inspect
      "#<#{self.class.name} id=#{id.inspect} prefix=#{prefix.inspect} digest=[FILTERED]>"
    end

    def revoke!(at = Time.current)
      return self if revoked_at?

      update!(revoked_at: at)
      self
    end

    # The digest is intentionally excluded even though it is stored securely.
    def snapshot
      ImmutableSnapshot.build(
        id: id,
        prefix: prefix,
        active_at: active_at,
        expires_at: expires_at,
        revoked_at: revoked_at
      )
    end

    private

    def expires_after_activation
      return if expires_at.nil? || active_at.nil? || expires_at > active_at

      errors.add(:expires_at, "must be after active_at")
    end

    def metadata_is_safe
      value = metadata || {}
      valid = value.is_a?(Hash) && value.all? { |key, item| !Redactor.secret_key?(key) && safe_value?(item) }
      errors.add(:metadata, "must be safe JSON without secrets") unless valid
    end

    def safe_value?(value)
      case value
      when Hash
        value.all? { |key, item| !Redactor.secret_key?(key) && safe_value?(item) }
      when Array
        value.all? { |item| safe_value?(item) }
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
