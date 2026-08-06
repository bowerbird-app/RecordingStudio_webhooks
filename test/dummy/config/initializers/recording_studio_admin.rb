# frozen_string_literal: true

RecordingStudioAdmin.configure do |config|
  config.engine_layout = "application"
  config.async_widgets.enabled = false
  config.access_recording_resolver = lambda do |context|
    context.controller.current_root_recording || RecordingStudio.root_recording_for(Workspace.order(:name).first)
  end
end

Rails.application.config.to_prepare do
  RecordingStudioAdmin::ApplicationController.helper ApplicationHelper
end