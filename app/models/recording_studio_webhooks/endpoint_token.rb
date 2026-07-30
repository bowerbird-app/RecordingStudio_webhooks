# frozen_string_literal: true

module RecordingStudioWebhooks
  class EndpointToken < ApplicationRecord
    recording_studio_recordable label: "Webhook Endpoint Token", root: false, allowed_parent_types: ["RecordingStudioWebhooks::Endpoint"] if respond_to?(:recording_studio_recordable)

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

    validates :digest, presence: true
    validates :prefix, presence: true, length: { maximum: 32 }
    validates :active_at, presence: true
    validate :expires_after_activation
    validate :safe_metadata

    before_update :prevent_credential_mutation
    before_destroy :prevent_destroy

    scope :current, lambda { |at = Time.current|
      joins("INNER JOIN recording_studio_recordings rs_recordings ON rs_recordings.recordable_type = '#{name}' AND rs_recordings.recordable_id = recording_studio_webhooks_endpoint_tokens.id")
        .where(revoked_at: nil)
        .where(arel_table[:active_at].lteq(at))
        .where(arel_table[:expires_at].eq(nil).or(arel_table[:expires_at].gt(at)))
    }
    scope :stable, lambda {
      joins("INNER JOIN recording_studio_recordings rs_recordings ON rs_recordings.recordable_type = '#{name}' AND rs_recordings.recordable_id = recording_studio_webhooks_endpoint_tokens.id")
    }

    def self.authenticate(plaintext:, endpoint: nil, at: Time.current)
      return unless plaintext.respond_to?(:to_str)

      value = plaintext.to_str
      scope = endpoint.is_a?(Endpoint) ? endpoint.endpoint_tokens.current(at) : current(at)

      if column_names.include?("token")
        direct = scope.find_by(token: value)
        return direct if direct
      end

      digest = TokenDigest.digest(value)
      token = scope.find_by(digest: digest)
      token if token && TokenDigest.secure_compare(digest, token.digest)
    end

    def current?(at = Time.current)
      return false unless revoked_at.nil? && active_at <= at && (expires_at.nil? || expires_at > at)

      stable_recording = RecordingStudioGateway.stable_recording_for(self)
      stable_recording.present? && stable_recording.recordable_id == id
    end

    def revoke!(at: Time.current, actor: nil)
      with_lock do
        return false unless current?(at)

        stable_recording = RecordingStudioGateway.stable_recording_for(self)
        raise RecordingStudioConfigurationError, "endpoint token recording is missing" unless stable_recording

        root_recording = endpoint.recording_studio_recording.root_recording_or_self
        revised_recording = RecordingStudioGateway.revise!(
          root_recording: root_recording,
          stable_recording: stable_recording,
          actor: actor,
          metadata: { endpoint_id: endpoint_id, endpoint_token_id: id }
        ) do |recordable|
          recordable.revoked_at = at
          recordable.revoked_by_actor_id = actor_identifier(actor)
        end

        replacement = self.class.find(revised_recording.recordable_id)
        replacement.audit!(
          action: "recording_studio_webhooks.endpoint_token.revoked",
          actor: actor,
          metadata: { endpoint_token_id: replacement.id, previous_endpoint_token_id: id, endpoint_id: endpoint_id },
          idempotency_key: "recording_studio_webhooks:endpoint-token-revocation:#{replacement.id}"
        )
        endpoint.audit!(
          action: "recording_studio_webhooks.endpoint_token.revoked",
          actor: actor,
          metadata: { endpoint_token_id: replacement.id, previous_endpoint_token_id: id, endpoint_id: endpoint_id },
          idempotency_key: "recording_studio_webhooks:endpoint-token-revocation:#{replacement.id}"
        )
        replacement
      end
    end

    def audit!(action:, actor: nil, metadata: {}, idempotency_key: nil)
      stable_recording = RecordingStudioGateway.stable_recording_for(self)
      raise RecordingStudioConfigurationError, "endpoint token recording is missing" unless stable_recording

      root_recording = endpoint.recording_studio_recording.root_recording_or_self
      RecordingStudioGateway.log_event!(
        root_recording: root_recording,
        recording: stable_recording,
        action: action,
        actor: actor,
        metadata: metadata,
        idempotency_key: idempotency_key
      )
    end

    def snapshot
      ImmutableSnapshot.build(
        id: id,
        endpoint_id: endpoint_id,
        prefix: prefix,
        active_at: active_at,
        expires_at: expires_at,
        revoked_at: revoked_at,
        revoked_by_actor_id: revoked_by_actor_id,
        metadata: metadata,
        created_at: created_at
      )
    end

    def inspect = "#<#{self.class.name} id=#{id.inspect} prefix=#{prefix.inspect} digest=[FILTERED]>"

    private

      def self.ensure_registered_recordable_type!
        return unless defined?(::RecordingStudio) && ::RecordingStudio.respond_to?(:register_recordable_type)

        type_name = name
        configured_types = Array(::RecordingStudio.configuration.recordable_types).map(&:to_s)
        return if configured_types.include?(type_name)

        ::RecordingStudio.register_recordable_type(type_name)
      rescue StandardError
        nil
      end

    def prevent_credential_mutation
      immutable = %w[endpoint_id digest prefix active_at expires_at metadata revoked_at revoked_by_actor_id]
      immutable.unshift("token") if self.class.column_names.include?("token")
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

    def actor_identifier(actor)
      return nil if actor.nil?

      if actor.respond_to?(:id) && actor.id.present?
        actor.id.to_s
      else
        actor.to_s.presence
      end
    end

    ensure_registered_recordable_type!
  end
end
