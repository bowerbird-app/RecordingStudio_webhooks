# frozen_string_literal: true

module RecordingStudioWebhooks
  module Admin
    class WebhooksController < BaseController
      def show
        redirect_to admin_webhooks_section_path
      end
    end
  end
end
