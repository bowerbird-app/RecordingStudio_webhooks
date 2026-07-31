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
    resources :providers, only: %i[index show], param: :name
    resources :events, only: :index
    get "webhook_sandbox", to: "sandboxes#show", as: :webhook_sandbox
    post "webhook_sandbox", to: "sandboxes#create"

    resources :endpoints, only: %i[index new create show edit update] do
      resources :tokens, only: %i[index create destroy]
      resources :events, only: %i[index show] do
        resources :action_plans, only: :show
      end
      resource :sandbox, only: :show
    end
  end
end
