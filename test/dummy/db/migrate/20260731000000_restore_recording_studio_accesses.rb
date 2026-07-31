# frozen_string_literal: true

class RestoreRecordingStudioAccesses < ActiveRecord::Migration[8.1]
  def change
    return if table_exists?(:recording_studio_accesses)

    create_table :recording_studio_accesses, id: :uuid do |table|
      table.string :actor_type, null: false
      table.uuid :actor_id, null: false
      table.integer :role, null: false, default: 0
      table.datetime :created_at, null: false
    end

    add_index :recording_studio_accesses, %i[actor_type actor_id], name: "index_recording_studio_accesses_on_actor"
    add_index :recording_studio_accesses, %i[actor_type actor_id role], name: "index_recording_studio_accesses_on_actor_and_role"
  end
end