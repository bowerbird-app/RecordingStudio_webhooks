# frozen_string_literal: true

require "i18n"

module RecordingStudioWebhooks
  # English copy for non-view user-facing strings (controller flashes and form
  # errors). Every lookup passes an English `default:` so a host locale with no
  # fallback never shows "translation missing".
  module Copy
    PREFIX = "recording_studio.webhooks"

    module_function

    def t(key, **options)
      I18n.t("#{PREFIX}.#{key}", **options)
    end
  end
end
