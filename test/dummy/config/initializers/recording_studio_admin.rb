# frozen_string_literal: true

RecordingStudioAdmin.configure do |config|
  config.engine_layout = "recording_studio/default_layout"
  config.async_widgets.enabled = false
  config.access_recording_resolver = lambda do |context|
    if context.controller.nil?
      admin_root = AdminRoot.find_by(name: "Admin")
      next RecordingStudio.root_recording_for(admin_root) if admin_root
    end

    context.controller&.current_root_recording ||
      RecordingStudio.root_recording_for(Workspace.order(:name).first)
  end
  config.site_admin_recording_resolver = lambda do |_context|
    admin_root = AdminRoot.find_by(name: "Admin")
    RecordingStudio.root_recording_for(admin_root) if admin_root
  end
end

Rails.application.config.to_prepare do
  RecordingStudioAdmin::ApplicationController.helper ApplicationHelper
end
