# frozen_string_literal: true

# lib/recording_studio_webhooks/engine.rb
require "rails/engine"

module RecordingStudioWebhooks
  class Engine < ::Rails::Engine
    isolate_namespace RecordingStudioWebhooks

    initializer "recording_studio_webhooks.protect_public_intake_parameters" do |app|
      app.middleware.use RecordingStudioWebhooks::PublicIntakeGuard
    end

    initializer "recording_studio_webhooks.filter_sensitive_admin_parameters" do |app|
      app.config.filter_parameters += %i[
        payload
        raw_payload
        identity_json
        metadata_json
        policy_json
        endpoint_token
      ]
    end

    initializer "recording_studio_webhooks.load_configuration" do |app|
      next unless app.config.respond_to?(:x) && app.config.x.respond_to?(:recording_studio_webhooks)

      configured = app.config.x.recording_studio_webhooks
      RecordingStudioWebhooks.configuration.merge!(configured.to_h) if configured.respond_to?(:to_h)
    end

    initializer "recording_studio_webhooks.discover_registrations" do
      config.to_prepare { RecordingStudioWebhooks.configuration.discover! }
    end

    initializer "recording_studio_webhooks.register_admin_section" do
      config.to_prepare { RecordingStudioWebhooks::Admin::Registration.register! }
    end

    initializer "recording_studio_webhooks.configure_recording_studio_recordables" do
      config.to_prepare { RecordingStudioWebhooks.configure_recordables! }
    end

    initializer "recording_studio_webhooks.patch_last_4_weeks_preset" do
      config.to_prepare do
        next unless defined?(RecordingStudioAdmin::Filters::DateRangeFilter)

        target = RecordingStudioAdmin::Filters::DateRangeFilter
        patch = RecordingStudioWebhooks::AdminLast4WeeksPatch::DateRangeFilter
        target.prepend(patch) unless target.ancestors.include?(patch)
      end
    end

    initializer "recording_studio_webhooks.prepend_admin_view_overrides" do
      config.to_prepare do
        view_path = RecordingStudioWebhooks::Engine.root.join("app/views").to_s

        if defined?(RecordingStudioAdmin::ScreensController)
          RecordingStudioAdmin::ScreensController.prepend_view_path(view_path)
        end

        if defined?(RecordingStudioAdmin::ScreenWidgetsController)
          RecordingStudioAdmin::ScreenWidgetsController.prepend_view_path(view_path)
        end
      end
    end
  end
end
