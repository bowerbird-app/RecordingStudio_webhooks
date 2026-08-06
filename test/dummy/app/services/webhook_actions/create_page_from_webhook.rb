# frozen_string_literal: true

module WebhookActions
  class CreatePageFromWebhook
    def self.call(context)
      new(context).call
    end

    def initialize(context)
      @context = context
    end

    def call
      title = payload.dig("data", "object", "title").to_s.strip
      raise ArgumentError, "payload data.object.title is required" if title.empty?

      root_recording = endpoint.recording_studio_recording.root_recording_or_self
      page = Page.new(title: title)
      RecordingStudio.record!(
        action: "created",
        recordable: page,
        root_recording: root_recording,
        parent_recording: root_recording
      )

      true
    end

    private

    attr_reader :context

    def payload
      context.payload
    end

    def endpoint
      context.endpoint
    end
  end
end