# frozen_string_literal: true

RecordingStudioWebhooks::Engine.routes.draw do
  post "inbound/:endpoint_token",
       to: "public/intake#create",
       as: :inbound,
       constraints: {
         endpoint_token: /rswh_[A-Za-z0-9_-]+/
       }

  scope module: :admin, as: :admin do
    root to: "webhooks#show"

    resource :webhooks, only: :show, controller: :webhooks
    resources :providers, only: %i[index], param: :name
    resources :events, only: :index
    get "tokens/new", to: "token_issuances#new", as: :new_token_issuance
    post "tokens", to: "token_issuances#create", as: :token_issuances
    get "webhook_sandbox", to: "sandboxes#show", as: :webhook_sandbox
    post "webhook_sandbox", to: "sandboxes#create"
    get "action_attempts/:id", to: "action_attempts#show", as: :action_attempt_short
    get "attempts/:id", to: "action_attempts#show", as: :action_attempt

    resources :endpoints, only: %i[index new create update] do
      resources :tokens, only: %i[create destroy]
      resources :events, only: %i[index] do
        resources :action_attempts, only: :show
      end
      resource :sandbox, only: :show
    end
  end
end
