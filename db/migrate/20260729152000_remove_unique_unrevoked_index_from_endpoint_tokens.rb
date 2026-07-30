# frozen_string_literal: true

class RemoveUniqueUnrevokedIndexFromEndpointTokens < ActiveRecord::Migration[8.1]
  def up
    remove_index :recording_studio_webhooks_endpoint_tokens,
      name: "index_rsw_tokens_one_unrevoked_per_endpoint",
      if_exists: true
  end

  def down
    add_index :recording_studio_webhooks_endpoint_tokens,
      :endpoint_id,
      unique: true,
      where: "revoked_at IS NULL",
      name: "index_rsw_tokens_one_unrevoked_per_endpoint",
      if_not_exists: true
  end
end
