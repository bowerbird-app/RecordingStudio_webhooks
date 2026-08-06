# frozen_string_literal: true

class MakeEndpointTokenDigestIndexNonUnique < ActiveRecord::Migration[8.1]
  def up
    remove_index :recording_studio_webhooks_endpoint_tokens,
      name: "index_recording_studio_webhooks_endpoint_tokens_on_digest",
      if_exists: true

    add_index :recording_studio_webhooks_endpoint_tokens,
      :digest,
      name: "index_recording_studio_webhooks_endpoint_tokens_on_digest",
      if_not_exists: true
  end

  def down
    remove_index :recording_studio_webhooks_endpoint_tokens,
      name: "index_recording_studio_webhooks_endpoint_tokens_on_digest",
      if_exists: true

    add_index :recording_studio_webhooks_endpoint_tokens,
      :digest,
      unique: true,
      name: "index_recording_studio_webhooks_endpoint_tokens_on_digest",
      if_not_exists: true
  end
end
