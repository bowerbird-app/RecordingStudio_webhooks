# frozen_string_literal: true

module RecordingStudioWebhooks
  class ApplicationController < ActionController::Base
    include RecordingStudio::RootSwitchable::ControllerSupport if defined?(RecordingStudio::RootSwitchable::ControllerSupport)

    protect_from_forgery with: :exception

    recording_studio_layout { RecordingStudioWebhooks.configuration.layout }

    private

    def webhook_configuration
      RecordingStudioWebhooks.configuration
    end
  end
end
