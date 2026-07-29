# frozen_string_literal: true

class UseRecordingIdEndpointsAndRevisioning < ActiveRecord::Migration[8.1]
  def up
    remove_index :recording_studio_webhooks_endpoints, name: "index_rsw_endpoints_on_provider_and_identity", if_exists: true

    add_index :recording_studio_webhooks_endpoints,
      %i[provider_name recording_studio_recording_id],
      name: "index_rsw_endpoints_on_provider_and_recording",
      if_not_exists: true

    remove_column :recording_studio_webhooks_endpoints, :identity_key, if_exists: true
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "identity_key removal is irreversible"
  end
end
