# frozen_string_literal: true

class AddSigningSecretToRecordingStudioWebhooksEndpoints < ActiveRecord::Migration[8.1]
  def up
    table = :recording_studio_webhooks_endpoints
    return if column_exists?(table, :signing_secret)

    add_column table, :signing_secret, :text
  end

  def down
    table = :recording_studio_webhooks_endpoints
    return unless column_exists?(table, :signing_secret)

    remove_column table, :signing_secret
  end
end
