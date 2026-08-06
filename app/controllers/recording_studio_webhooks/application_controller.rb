# frozen_string_literal: true

module RecordingStudioWebhooks
  class ApplicationController < ActionController::Base
    include RecordingStudio::RootSwitchable::ControllerSupport if defined?(RecordingStudio::RootSwitchable::ControllerSupport)

    protect_from_forgery with: :exception

    layout "recording_studio_webhooks/application"

    private

    def webhook_configuration
      RecordingStudioWebhooks.configuration
    end
  end
end
