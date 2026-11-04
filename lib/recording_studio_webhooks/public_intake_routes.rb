# frozen_string_literal: true

RecordingStudioWebhooks::Engine.routes.append { post "inbound", to: "public/intake#create", as: :inbound_header }
