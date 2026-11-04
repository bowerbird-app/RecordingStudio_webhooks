# frozen_string_literal: true

module RecordingStudioWebhooks
  # Keeps Rails' generic request parameter parser and logger from reading an
  # inbound JSON body before the intake service can redact it. The controller
  # reads Rack input with a bounded read instead.
  class PublicIntakeGuard
    INVALID_BODY = '{"status":"invalid"}'
    TOKEN_SUFFIX = %r{\A/rswh_[A-Za-z0-9_-]+\z}

    class << self
      attr_accessor :mount_path
    end

    def initialize(app)
      @app = app
    end

    def call(environment)
      return @app.call(environment) unless public_intake_request?(environment)

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

    def public_intake_request?(environment)
      return false unless environment.fetch("REQUEST_METHOD", "").upcase == "POST"

      mount = resolved_mount_path
      return false if mount.nil? || mount.empty?

      inbound = "#{mount.delete_suffix('/')}/inbound"
      path = environment.fetch("PATH_INFO", "")
      return true if path == inbound

      remainder = path.delete_prefix(inbound)
      remainder != path && TOKEN_SUFFIX.match?(remainder)
    end

    def resolved_mount_path
      self.class.mount_path || discover_engine_mount_path
    end

    def discover_engine_mount_path
      return nil unless defined?(Rails) && Rails.respond_to?(:application)

      application = Rails.application
      return nil unless application.respond_to?(:routes)

      application.routes.routes.each do |route|
        next unless mounted_webhooks_engine?(route)

        return route.path.spec.to_s.sub("(.:format)", "").delete_suffix("/")
      end
      nil
    end

    def mounted_webhooks_engine?(route)
      unwrap_rack_app(route.app) == RecordingStudioWebhooks::Engine
    end

    def unwrap_rack_app(app)
      current = app
      8.times do
        return current if current == RecordingStudioWebhooks::Engine
        break unless current.respond_to?(:app) && !current.is_a?(Class)

        current = current.app
      end
      current
    end

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
