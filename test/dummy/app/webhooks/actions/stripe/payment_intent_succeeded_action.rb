# frozen_string_literal: true

module Webhooks
  module Actions
    module Stripe
      class PaymentIntentSucceededAction < RecordingStudioWebhooks::Action
        def self.call(_context)
          true
        end

        def self.register!
          register(
            "stripe.payment_intent_succeeded",
            provider: "stripe",
            event: "payment_intent.succeeded",
            policy: { max_retries: 2 }
          )
        end
      end
    end
  end
end

Webhooks::Actions::Stripe::PaymentIntentSucceededAction.register!
