# frozen_string_literal: true

module RecordingStudioWebhooks
  module Admin
    class ProvidersController < BaseController
      def index
        @providers = webhook_configuration.providers.all.sort_by(&:name)
        @provider_endpoint_counts = endpoint_scope.group(:provider_name).count
      end

      def show
        @provider = webhook_configuration.providers.fetch(params[:name])
        raise ActionController::RoutingError, "Not Found" unless @provider

        @provider_snapshot = @provider.snapshot
        @provider_defaults = Policy.new(
          Policy::DEFAULT_VALUES
            .merge(webhook_configuration.framework_policy_overrides)
            .merge(webhook_configuration.default_policy_overrides)
            .merge(webhook_configuration.global_policy_overrides)
            .merge(@provider.policy_overrides)
        )
        @matching_actions = webhook_configuration.actions.all
                                                 .select { |action| action.provider_name.nil? || action.provider_name == @provider.name }
                                                 .sort_by(&:sort_key)
        provider_endpoints = endpoint_scope.where(provider_name: @provider.name)

        @endpoints = provider_endpoints
                     .includes(:endpoint_tokens)
                     .order(created_at: :desc)

        @incoming_events = InboundEvent
                           .includes(:endpoint)
                           .where(endpoint_id: provider_endpoints.select(:id))
                           .order(received_at: :desc)
                           .limit(50)
      end
    end
  end
end
