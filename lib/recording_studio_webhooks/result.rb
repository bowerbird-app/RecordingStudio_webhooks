# frozen_string_literal: true

# lib/recording_studio_webhooks/result.rb
module RecordingStudioWebhooks
  # Results are safe to render from a public controller: they never retain input
  # payloads, credentials, headers, or exception messages.
  class Result
    attr_reader :status, :code, :record, :details

    def initialize(status:, code:, record: nil, details: {})
      @status = Integer(status)
      @code = code.to_s.freeze
      @record = record
      @details = ImmutableSnapshot.build(details)
      freeze
    end

    def success? = status.between?(200, 299)

    def failure? = !success?

    def to_h
      ImmutableSnapshot.build(status: status, code: code, details: details)
    end
  end
end
