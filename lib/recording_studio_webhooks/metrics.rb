# frozen_string_literal: true

require_relative "api/access"
require "recording_studio_metrics"

module RecordingStudioWebhooks
  module Metrics
    EVENTS = :webhook_events
    ATTEMPTS = :webhook_attempts
    ENDPOINTS = :webhook_endpoints
    API = :operations
    EXPOSE = { api: [API] }.freeze
    AUTHORIZE = ->(context) { RecordingStudioWebhooks::Api::Access.can_view?(context) }
    ENABLED = ->(relation) { relation.where(enabled: true) }
    CURRENT_ENDPOINTS = ->(relation) { relation.merge(RecordingStudioWebhooks::Endpoint.current) }

    module_function

    def install!
      prepend_admin_view_overrides
      register!
    end

    def register!
      return if RecordingStudioMetrics.find("webhook_events.over_time")

      register_events!
      register_attempts!
      register_endpoints!
    end

    def prepend_admin_view_overrides
      view_path = RecordingStudioWebhooks::Engine.root.join("app/views").to_s
      if defined?(RecordingStudioAdmin::ScreensController)
        RecordingStudioAdmin::ScreensController.prepend_view_path(view_path)
      end
      return unless defined?(RecordingStudioAdmin::ScreenWidgetsController)

      RecordingStudioAdmin::ScreenWidgetsController.prepend_view_path(view_path)
    end

    def register_events!
      RecordingStudioMetrics.register(
        EVENTS,
        model: RecordingStudioWebhooks::InboundEvent,
        blast_radius: :site,
        api_authorize: AUTHORIZE
      ) { RecordingStudioWebhooks::Metrics.define_events(self) }
    end

    def register_attempts!
      RecordingStudioMetrics.register(
        ATTEMPTS,
        model: RecordingStudioWebhooks::ActionAttempt,
        blast_radius: :site,
        api_authorize: AUTHORIZE
      ) { RecordingStudioWebhooks::Metrics.define_attempts(self) }
    end

    def register_endpoints!
      RecordingStudioMetrics.register(
        ENDPOINTS,
        model: RecordingStudioWebhooks::Endpoint,
        blast_radius: :site,
        api_authorize: AUTHORIZE,
        scope: CURRENT_ENDPOINTS
      ) { RecordingStudioWebhooks::Metrics.define_endpoints(self) }
    end

    def define_events(dsl)
      dsl.timeseries :over_time, title: "Webhook events over time", field: :received_at, expose: EXPOSE
      dsl.breakdown :by_provider, title: "Webhook events by provider", field: :provider_name, expose: EXPOSE
    end

    def define_attempts(dsl)
      dsl.breakdown :by_status, title: "Webhook attempts by status", field: :status, expose: EXPOSE
    end

    def define_endpoints(dsl)
      dsl.count :enabled, title: "Enabled webhook endpoints", expose: EXPOSE, scope: ENABLED
    end
  end
end
