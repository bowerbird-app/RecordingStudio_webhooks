# frozen_string_literal: true

module RecordingStudioWebhooks
  # Keeps Rails' generic request parameter parser and logger from reading an
  # inbound JSON body before the intake service can redact it. The controller
  # reads Rack input with a bounded read instead.
  class PublicIntakeGuard
    INBOUND_PATH = %r{(?:\A|/)inbound/rswh_[A-Za-z0-9_-]+\z}.freeze
    INVALID_BODY = '{"status":"invalid"}'

    def initialize(app)
      @app = app
    end

    def call(environment)
      return @app.call(environment) unless INBOUND_PATH.match?(environment.fetch("PATH_INFO", ""))

      limit = RecordingStudioWebhooks.configuration.max_payload_bytes
      return payload_too_large if declared_body_too_large?(environment["CONTENT_LENGTH"], limit)

      environment["recording_studio_webhooks.public_intake"] = true
      # ActionDispatch uses these caches before attempting JSON parameter
      # parsing. Leave path values in their dedicated cache for routing.
      environment["action_dispatch.request.request_parameters"] = {}
      environment["action_dispatch.request.parameters"] = {}
      @app.call(environment)
    end

    private

    def declared_body_too_large?(content_length, limit)
      return false unless /\A\d+\z/.match?(content_length.to_s)

      content_length.to_i > limit
    end

    def payload_too_large
      [
        413,
        {
          "content-type" => "application/json; charset=utf-8",
          "content-length" => INVALID_BODY.bytesize.to_s
        },
        [INVALID_BODY]
      ]
    end
  end
end
