# frozen_string_literal: true

module RecordingStudioWebhooks
  module Api
    module EndpointRegistrations
      TAGS = ["Webhook Endpoints"].freeze
      TOKEN_TAGS = ["Webhook Tokens"].freeze

      INDEX = {
        http_verb: :get,
        path: "webhook-endpoints",
        handler: Endpoints::Index,
        openapi: {
          title: "Webhook Endpoint - List",
          summary: "List webhook endpoints in this workspace.",
          description: "List webhook endpoints in the token's root.",
          tags: TAGS
        }
      }.freeze

      SHOW = {
        http_verb: :get,
        path: "webhook-endpoints/:id",
        handler: Endpoints::Show,
        openapi: {
          title: "Webhook Endpoint - Show",
          summary: "Show one webhook endpoint.",
          description: "Show one webhook endpoint in the token's root.",
          tags: TAGS
        }
      }.freeze

      CREATE = {
        http_verb: :post,
        path: "webhook-endpoints",
        handler: Endpoints::Create,
        input_contract: {
          reject_unknown: true,
          fields: {
            label: { type: :string, required: true, allow_blank: false },
            provider_name: { type: :string, required: true, allow_blank: false },
            enabled: { type: :boolean, required: false },
            identity: { type: :hash, required: false },
            metadata: { type: :hash, required: false },
            policy_overrides: { type: :hash, required: false }
          }
        },
        openapi: {
          title: "Webhook Endpoint - Create",
          summary: "Create a webhook endpoint.",
          description: "Create a webhook endpoint on the token's root.",
          tags: TAGS
        }
      }.freeze

      UPDATE = {
        http_verb: :patch,
        path: "webhook-endpoints/:id",
        handler: Endpoints::Update,
        input_contract: {
          reject_unknown: true,
          fields: {
            id: { type: :string, required: true, allow_blank: false },
            label: { type: :string, required: false, allow_blank: false },
            enabled: { type: :boolean, required: false }
          }
        },
        openapi: {
          title: "Webhook Endpoint - Update",
          summary: "Update a webhook endpoint.",
          description: "Update a webhook endpoint's label or enabled flag.",
          tags: TAGS
        }
      }.freeze

      ISSUE = {
        http_verb: :post,
        path: "webhook-endpoints/:id/tokens",
        handler: Endpoints::Issue,
        input_contract: {
          reject_unknown: true,
          fields: {
            id: { type: :string, required: true, allow_blank: false },
            expires_at: { type: :string, required: false }
          }
        },
        openapi: {
          title: "Webhook Token - Issue",
          summary: "Issue a webhook token. The plaintext shows once.",
          description: "Issue a webhook endpoint token. The plaintext token is returned only in this response.",
          tags: TOKEN_TAGS
        }
      }.freeze

      REVOKE = {
        http_verb: :post,
        path: "webhook-tokens/:id/revoke",
        handler: Endpoints::Revoke,
        openapi: {
          title: "Webhook Token - Revoke",
          summary: "Revoke a webhook token.",
          description: "Revoke a webhook endpoint token in the token's root.",
          tags: TOKEN_TAGS
        }
      }.freeze
    end
  end
end
