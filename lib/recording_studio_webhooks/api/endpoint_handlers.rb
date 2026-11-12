# frozen_string_literal: true

module RecordingStudioWebhooks
  module Api
    module Endpoints
      class Index
        def self.call(context)
          Endpoints.authorize!(context)
          endpoints = Endpoints.scoped_endpoints(context).order(:created_at, :id)
          { records: endpoints.map { |endpoint| Endpoints.serialize_endpoint(endpoint) } }
        end
      end

      class Show
        def self.call(context)
          Endpoints.authorize!(context)
          Endpoints.serialize_endpoint(Endpoints.find_endpoint!(context))
        end
      end

      class Create
        def self.call(context)
          Endpoints.authorize!(context)
          created = EndpointLifecycle.create!(
            endpoint: Endpoint.new(Endpoints.create_attributes(context)),
            actor: context.access_grant.actor
          )
          Endpoints.serialize_endpoint(created)
        end
      end

      class Update
        def self.call(context)
          Endpoints.authorize!(context)
          attributes = context.params.slice(:label, :enabled)
          updated = EndpointLifecycle.update!(
            endpoint: Endpoints.find_endpoint!(context),
            attributes: attributes,
            actor: context.access_grant.actor
          )
          Endpoints.serialize_endpoint(updated)
        end
      end

      class Issue
        def self.call(context)
          Endpoints.authorize!(context)
          issuance = Endpoints.find_endpoint!(context).issue_token!(
            expires_at: parsed_expiration(context.params[:expires_at]),
            actor: context.access_grant.actor
          )
          Endpoints.serialize_token(issuance.endpoint_token, plaintext_token: issuance.plaintext_token)
        end

        def self.parsed_expiration(value)
          return if value.blank?

          Time.zone.parse(value.to_s) || raise(
            RecordingStudioApi::InvalidActionInputError,
            "expires_at must be a valid time"
          )
        end
      end

      class Revoke
        def self.call(context)
          Endpoints.authorize!(context)
          revoked = Endpoints.find_token!(context).revoke!(actor: context.access_grant.actor)
          raise RecordingStudioApi::NotFoundError, "Webhook token was not found" unless revoked

          Endpoints.serialize_token(revoked)
        end
      end
    end
  end
end
