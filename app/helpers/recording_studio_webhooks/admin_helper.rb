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

    def admin_webhooks_section_path
      proxy = recording_studio_admin_engine_proxy
      return proxy.section_path("admin_webhooks") if proxy&.respond_to?(:section_path)

      mount = if defined?(RecordingStudioAdmin)
                RecordingStudioAdmin.configuration.default_mount_path.to_s.chomp("/")
              else
                "/admin"
              end
      "#{mount}/sections/admin_webhooks"
    end

    private

    def recording_studio_admin_engine_proxy
      return unless defined?(main_app)

      %i[recording_studio_admin_admin recording_studio_admin_webhooks recording_studio_admin].each do |name|
        next unless main_app.respond_to?(name)

        proxy = main_app.public_send(name)
        return proxy if proxy.respond_to?(:section_path)
      end

      nil
    end
  end
end
