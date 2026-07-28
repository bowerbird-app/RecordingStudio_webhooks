# frozen_string_literal: true

RecordingStudioWebhooks::Engine.routes.draw do
  post "inbound/:provider/:endpoint_identity",
    to: "public/intake#create",
    as: :inbound,
    constraints: {
      provider: /[a-z][a-z0-9_-]*/,
      endpoint_identity: /[a-z0-9][a-z0-9_-]{2,127}/
    }

  namespace :admin do
    root to: "endpoints#index"

    resources :endpoints, only: %i[index new create show edit update] do
      resources :tokens, only: %i[index create destroy]
      resources :events, only: %i[index show] do
        resources :action_plans, only: :show
      end
      resource :sandbox, only: %i[show create]
    end
  end
end
