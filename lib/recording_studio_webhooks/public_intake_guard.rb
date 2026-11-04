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

      def reset_discovered_mount_path!
        EngineMount.reset!
      end

      def discover_engine_mount_path
        EngineMount.discover
      end
    end

    module EngineMount
      UNSET = Object.new.freeze
      private_constant :UNSET

      class << self
        def reset!
          @discovered_mount_path = UNSET
        end

        def discover
          return @discovered_mount_path if cached?
          return nil unless routes_ready?

          @discovered_mount_path = scan
        end

        private

        def cached?
          instance_variable_defined?(:@discovered_mount_path) && !@discovered_mount_path.equal?(UNSET)
        end

        def routes_ready?
          application = rails_application
          return false unless application
          return false unless application.respond_to?(:routes)
          return true if application.respond_to?(:initialized?) && application.initialized?

          collection = application.routes
          collection.respond_to?(:routes) && collection.routes.any?
        end

        def rails_application
          return nil unless defined?(Rails) && Rails.respond_to?(:application)

          Rails.application
        end

        def scan
          application = rails_application
          return nil unless application
          return nil unless application.respond_to?(:routes)

          application.routes.routes.each do |route|
            next unless mounted_webhooks_engine?(route)

            return normalize(route.path.spec.to_s)
          end
          nil
        end

        def normalize(spec)
          trimmed = spec.sub("(.:format)", "").delete_suffix("/")
          trimmed.empty? ? "/" : trimmed
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
      end
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
      self.class.mount_path || self.class.discover_engine_mount_path
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
