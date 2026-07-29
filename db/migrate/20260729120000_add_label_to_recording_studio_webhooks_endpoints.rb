# frozen_string_literal: true

class AddLabelToRecordingStudioWebhooksEndpoints < ActiveRecord::Migration[8.1]
  def up
    add_column :recording_studio_webhooks_endpoints, :label, :string

    execute <<~SQL.squish
      UPDATE recording_studio_webhooks_endpoints
      SET label = identity_key
      WHERE label IS NULL OR label = ''
    SQL

    change_column_null :recording_studio_webhooks_endpoints, :label, false
  end

  def down
    remove_column :recording_studio_webhooks_endpoints, :label
  end
end
