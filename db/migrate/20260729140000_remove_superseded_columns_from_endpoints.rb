# frozen_string_literal: true

class RemoveSupersededColumnsFromEndpoints < ActiveRecord::Migration[8.1]
  def up
    remove_index :recording_studio_webhooks_endpoints,
      name: "index_rsw_endpoints_on_provider_and_recording_current",
      if_exists: true

    remove_column :recording_studio_webhooks_endpoints, :superseded_at, if_exists: true
    remove_reference :recording_studio_webhooks_endpoints,
      :superseded_by_endpoint,
      foreign_key: { to_table: :recording_studio_webhooks_endpoints },
      if_exists: true

    add_index :recording_studio_webhooks_endpoints,
      %i[provider_name recording_studio_recording_id],
      name: "index_rsw_endpoints_on_provider_and_recording",
      if_not_exists: true
  end

  def down
    add_column :recording_studio_webhooks_endpoints, :superseded_at, :datetime unless column_exists?(:recording_studio_webhooks_endpoints, :superseded_at)
    add_reference :recording_studio_webhooks_endpoints,
      :superseded_by_endpoint,
      type: :uuid,
      foreign_key: { to_table: :recording_studio_webhooks_endpoints },
      if_not_exists: true

    remove_index :recording_studio_webhooks_endpoints,
      name: "index_rsw_endpoints_on_provider_and_recording",
      if_exists: true

    add_index :recording_studio_webhooks_endpoints,
      %i[provider_name recording_studio_recording_id],
      unique: true,
      where: "superseded_at IS NULL",
      name: "index_rsw_endpoints_on_provider_and_recording_current",
      if_not_exists: true
  end
end
