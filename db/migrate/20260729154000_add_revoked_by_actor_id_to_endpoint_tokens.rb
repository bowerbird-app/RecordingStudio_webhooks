# frozen_string_literal: true

class AddRevokedByActorIdToEndpointTokens < ActiveRecord::Migration[8.1]
  def change
    add_column :recording_studio_webhooks_endpoint_tokens, :revoked_by_actor_id, :string
  end
end
