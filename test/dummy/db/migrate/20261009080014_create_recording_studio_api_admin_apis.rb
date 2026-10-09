# frozen_string_literal: true

class CreateRecordingStudioApiAdminApis < ActiveRecord::Migration[8.1]
  def change
    create_table :recording_studio_api_admin_apis, id: :uuid do |t|
      t.string :key, null: false
      t.string :name, null: false

      t.timestamps
    end

    add_index :recording_studio_api_admin_apis, :key, unique: true
  end
end