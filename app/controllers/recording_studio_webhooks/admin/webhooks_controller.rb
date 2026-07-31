# frozen_string_literal: true

module RecordingStudioWebhooks
  module Admin
    class WebhooksController < BaseController
      def show
        redirect_to "#{main_app.recording_studio_admin_webhooks_path}/sections/admin_webhooks"
      end
    end
  end
end
