# frozen_string_literal: true

module RecordingStudioWebhooks
  module Admin
    class EndpointsController < BaseController
      before_action :load_endpoint, only: %i[show edit update]
      before_action :authorize_admin_webhooks_write!, only: %i[create update]

      def index
        @providers = webhook_configuration.providers.all.sort_by(&:name)
        @selected_provider = params[:provider].to_s.presence

        scope = endpoint_scope.includes(:recording_studio_recording, :endpoint_tokens).order(created_at: :desc)
        scope = scope.where(provider_name: @selected_provider) if @selected_provider.present?
        @endpoints = scope
      end

      def new
        @endpoint = Endpoint.new(enabled: true, identity: {}, metadata: {}, policy_overrides: {})
      end

      def create
        @endpoint = Endpoint.new(endpoint_attributes)
        @endpoint.recording_studio_recording_id = selected_recording.id

        if @form_error.nil? && registered_provider?
          issuance = nil
          Endpoint.transaction do
            EndpointLifecycle.create!(endpoint: @endpoint, actor: current_admin_actor)
            issuance = @endpoint.issue_token!(actor: current_admin_actor)
          end

          @issued_token = issuance.plaintext_token
          @endpoint_url = "#{request.base_url}#{inbound_path(provider: @endpoint.provider_name, endpoint_identity: @endpoint.identity_key)}"
          response.headers["Cache-Control"] = "no-store, max-age=0"
          response.headers["Pragma"] = "no-cache"
          render "recording_studio_webhooks/admin/tokens/show", status: :created
        else
          @form_error ||= "Choose a registered provider." unless registered_provider?
          render :new, status: :unprocessable_entity
        end
      rescue ActiveRecord::RecordInvalid
        render :new, status: :unprocessable_entity
      rescue ActiveRecord::RecordNotFound
        raise ActionController::RoutingError, "Not Found"
      end

      def show
        @provider = webhook_configuration.providers.fetch(@endpoint.provider_name)
        @tokens = @endpoint.endpoint_tokens.order(created_at: :desc)
        @events = @endpoint.inbound_events.includes(:action_plans).order(received_at: :desc).limit(20)
      end

      def edit
      end

      def update
        attributes = endpoint_update_attributes
        if @form_error.nil?
          EndpointLifecycle.update!(
            endpoint: @endpoint,
            attributes: attributes,
            actor: current_admin_actor
          )
          redirect_to admin_endpoint_path(@endpoint), notice: "Endpoint updated."
        else
          render :edit, status: :unprocessable_entity
        end
      rescue ActiveRecord::RecordInvalid
        render :edit, status: :unprocessable_entity
      end

      private

      def selected_recording
        current_root = current_root_recording_for_assignment
        raise ActiveRecord::RecordNotFound unless current_root

        available_recordings.find(current_root.id)
      end

      def current_root_recording_for_assignment
        return unless respond_to?(:current_root_recording, true)

        root = send(:current_root_recording)
        return unless root.present?

        available_recordings.find_by(id: root.id)
      rescue StandardError
        nil
      end

      def endpoint_attributes
        fields = endpoint_fields
        {
          provider_name: fields[:provider_name],
          identity_key: fields[:identity_key],
          enabled: cast_boolean(fields[:enabled]),
          identity: parsed_json_object(fields[:identity_json], "identity"),
          metadata: parsed_json_object(fields[:metadata_json], "metadata"),
          policy_overrides: parsed_json_object(fields[:policy_json], "policy")
        }
      end

      def endpoint_update_attributes
        fields = endpoint_fields
        {
          enabled: cast_boolean(fields[:enabled]),
          metadata: parsed_json_object(fields[:metadata_json], "metadata"),
          policy_overrides: parsed_json_object(fields[:policy_json], "policy")
        }
      end

      def endpoint_fields
        params.require(:endpoint).permit(
          :recording_studio_recording_id,
          :provider_name,
          :identity_key,
          :enabled,
          :identity_json,
          :metadata_json,
          :policy_json
        )
      end

      def parsed_json_object(value, label)
        text = value.to_s.strip
        return {} if text.empty?

        parsed = JSON.parse(text)
        raise JSON::ParserError unless parsed.is_a?(Hash)

        parsed
      rescue JSON::ParserError
        @form_error = "#{label.capitalize} must be a JSON object."
        {}
      end

      def cast_boolean(value)
        ActiveModel::Type::Boolean.new.cast(value)
      end

      def registered_provider?
        webhook_configuration.providers.fetch(@endpoint.provider_name).present?
      end
    end
  end
end
