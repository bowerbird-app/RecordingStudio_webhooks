# frozen_string_literal: true

class AllowNullAccessRecordingOnApiClients < ActiveRecord::Migration[8.1]
  def change
    change_column_null :recording_studio_api_api_clients, :access_recording_id, true
  end
end
