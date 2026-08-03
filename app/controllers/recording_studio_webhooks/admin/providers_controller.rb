# frozen_string_literal: true

module RecordingStudioWebhooks
  module Admin
    class ProvidersController < BaseController
      def index
        @providers = webhook_configuration.providers.all.sort_by(&:name)
        @provider_endpoint_counts = endpoint_scope.group(:provider_name).count
      end
    end
  end
end
