# frozen_string_literal: true

module RecordingStudioWebhooks
  # Rails filters query parameters, not path segments. Intake tokens use the
  # rswh_ prefix, so the request log line can redact that segment.
  module FilteredInboundPath
    TOKEN_SEGMENT = /rswh_[A-Za-z0-9_-]+/

    def filtered_path
      super.gsub(TOKEN_SEGMENT, "[FILTERED]")
    end
  end
end
