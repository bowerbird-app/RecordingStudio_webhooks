# frozen_string_literal: true

module Webhooks
  module Actions
    module Demo
      class PageCreated < RecordingStudioWebhooks::Action
        def self.call(context)
          WebhookActions::CreatePageFromWebhook.call(context)
        end

        def self.register!
          register(
            "demo.page_created",
            provider: "demo",
            event: "page.created",        
            policy: { max_retries: 0 }
          )
        end
      end
    end
  end
end

Webhooks::Actions::Demo::PageCreated.register!
