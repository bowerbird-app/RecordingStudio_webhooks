# frozen_string_literal: true

module RecordingStudioWebhooks
  module Api
    module Endpoints
      ROLE = :admin
      INDEX = :webhook_endpoints_index
      SHOW = :webhook_endpoints_show
      CREATE = :webhook_endpoints_create
      UPDATE = :webhook_endpoints_update
      ISSUE = :webhook_tokens_issue
      REVOKE = :webhook_tokens_revoke
      ENDPOINT_JSON_KEYS = %w[
        id recording_studio_recording_id label provider_name enabled
        identity metadata policy_overrides created_at updated_at
      ].freeze
      TOKEN_JSON_KEYS = %w[id endpoint_id prefix active_at expires_at revoked_at created_at].freeze

      module_function

      def register!
        return unless defined?(::RecordingStudioApi)
        return if RecordingStudioApi.registered_endpoint(INDEX)

        RecordingStudioApi.register_endpoint(INDEX, **EndpointRegistrations::INDEX)
        RecordingStudioApi.register_endpoint(SHOW, **EndpointRegistrations::SHOW)
        RecordingStudioApi.register_endpoint(CREATE, **EndpointRegistrations::CREATE)
        RecordingStudioApi.register_endpoint(UPDATE, **EndpointRegistrations::UPDATE)
        RecordingStudioApi.register_endpoint(ISSUE, **EndpointRegistrations::ISSUE)
        RecordingStudioApi.register_endpoint(REVOKE, **EndpointRegistrations::REVOKE)
      end

      def authorize!(context)
        context.access_grant.authorize!(recording: context.root_recording, role: ROLE)
        authorizer = RecordingStudioWebhooks.configuration.admin_authorizer
        return if authorizer && authorizer.call(admin_context(context, permission: :admin)) == true

        raise RecordingStudioApi::AuthorizationError, "API access grant is not authorized for this capability"
      end

      def scoped_endpoints(context)
        resolver = RecordingStudioWebhooks.configuration.admin_recording_scope
        return Endpoint.none unless resolver

        recordings = resolver.call(admin_context(context, permission: :view))
        Endpoint.current.where(recording_studio_recording_id: recordings.select(:id))
      rescue StandardError => e
        Rails.logger.warn(
          "RecordingStudioWebhooks::Api::Endpoints.scoped_endpoints failed: #{e.class}: #{e.message}"
        )
        Endpoint.none
      end

      def find_endpoint!(context)
        endpoint = scoped_endpoints(context).find_by(id: context.params[:id])
        return endpoint if endpoint

        raise RecordingStudioApi::NotFoundError, "Webhook endpoint was not found"
      end

      def find_token!(context)
        token = EndpointToken.find_by(id: context.params[:id])
        return token if token && scoped_endpoints(context).exists?(id: token.endpoint_id)

        raise RecordingStudioApi::NotFoundError, "Webhook token was not found"
      end

      def admin_context(context, permission:)
        Admin::BaseController::AdminContext.new(
          controller: nil,
          actor: Access.actor_for(context),
          section_key: Admin::BaseController::ADMIN_WEBHOOKS_SECTION_KEY,
          permission: permission,
          recording: context.root_recording
        )
      end

      def serialize_endpoint(endpoint)
        endpoint.as_json(only: ENDPOINT_JSON_KEYS)
      end

      def serialize_token(token, plaintext_token: nil)
        payload = token.as_json(only: TOKEN_JSON_KEYS)
        payload["token"] = plaintext_token unless plaintext_token.nil?
        payload
      end

      def object_hash(value)
        return {} if value.nil?

        value.to_h.deep_stringify_keys
      end

      def create_attributes(context)
        params = context.params
        {
          recording_studio_recording_id: context.root_recording.id,
          label: params[:label],
          provider_name: params[:provider_name],
          enabled: params.key?(:enabled) ? params[:enabled] : true,
          identity: object_hash(params[:identity]),
          metadata: object_hash(params[:metadata]),
          policy_overrides: object_hash(params[:policy_overrides])
        }
      end
    end
  end
end
