# frozen_string_literal: true

module RecordingStudioWebhooks
  module AdminHelper
    def webhook_status_style(status)
      return :success if %w[accepted planned succeeded].include?(status)
      return :danger if %w[failed].include?(status)
      return :warning if %w[retry_scheduled skipped].include?(status)

      :info
    end

    def pretty_webhook_json(value)
      JSON.pretty_generate(value || {})
    end
  end
end
