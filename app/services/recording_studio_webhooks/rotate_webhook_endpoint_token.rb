# frozen_string_literal: true

# app/services/recording_studio_webhooks/rotate_webhook_endpoint_token.rb
module RecordingStudioWebhooks
  # Reissues a token by revising the one stable token Recording under an
  # endpoint. It never creates a second token identity.
  class RotateWebhookEndpointToken
    class Issuance
      attr_reader :endpoint_token_recording, :endpoint_token_snapshot

      def initialize(endpoint_token_recording:, endpoint_token_snapshot:, plaintext_token:)
        @endpoint_token_recording = endpoint_token_recording
        @endpoint_token_snapshot = endpoint_token_snapshot
        @plaintext_token = plaintext_token
      end

      def plaintext_token
        raise Error, "plaintext token has already been disclosed" unless @plaintext_token

        token = @plaintext_token
        @plaintext_token = nil
        token
      end
      alias token plaintext_token

      def inspect = "#<#{self.class.name} endpoint_token_recording_id=#{endpoint_token_recording.id.inspect} token=[FILTERED]>"
    end

    def self.call(...) = new(...).call

    def initialize(endpoint_recording:, expires_at: nil, metadata: {}, active_at: Time.current, actor: nil)
      @endpoint_recording = endpoint_recording
      @expires_at = expires_at
      @metadata = metadata
      @active_at = active_at
      @actor = actor
    end

    def call
      return unavailable unless RecordingStudioGateway.available?

      plaintext_token = "rswh_#{SecureRandom.urlsafe_base64(32)}"
      token_recording = nil
      root = @endpoint_recording&.root_recording_or_self

      @endpoint_recording.with_lock do
        token_recording = stable_token_recording!
        token_recording = RecordingStudioGateway.revise!(
          root_recording: root,
          stable_recording: token_recording,
          actor: @actor,
          metadata: { source: "recording_studio_webhooks", operation: "token_reissued" }
        ) do |snapshot|
          snapshot.assign_attributes(
            digest: TokenDigest.digest(plaintext_token),
            prefix: plaintext_token.first(13),
            enabled: true,
            active_at: @active_at,
            expires_at: @expires_at,
            metadata: @metadata || {}
          )
        end

        RecordingStudioGateway.log_event!(
          root_recording: root,
          recording: @endpoint_recording,
          actor: @actor,
          action: "recording_studio_webhooks.endpoint_token.reissued",
          metadata: {
            endpoint_recording_id: @endpoint_recording.id,
            endpoint_token_recording_id: token_recording.id
          }
        )
      end

      Result.new(
        status: 201,
        code: "endpoint_token_reissued",
        record: Issuance.new(
          endpoint_token_recording: token_recording,
          endpoint_token_snapshot: token_recording.recordable,
          plaintext_token: plaintext_token
        )
      )
    rescue RecordingStudioUnavailableError, RecordingStudioConfigurationError
      unavailable
    rescue TokenIdentityConflictError
      Result.new(status: 409, code: "token_identity_conflict")
    rescue ActiveRecord::RecordInvalid, ArgumentError
      Result.new(status: 422, code: "token_invalid")
    rescue StandardError
      Result.new(status: 503, code: "token_unavailable")
    end

    private

    def unavailable = Result.new(status: 503, code: "recording_studio_unavailable")

    def stable_token_recording!
      records = @endpoint_recording.child_recordings
        .where(recordable_type: WebhookEndpointToken.name)
        .order(:id)
        .to_a
      raise RecordingStudioConfigurationError, "endpoint token identity is missing" if records.empty?
      raise TokenIdentityConflictError, "endpoint has more than one token identity" if records.size > 1

      records.first
    end
  end
end
