# frozen_string_literal: true

class RemovePlaintextTokenFromEndpointTokens < ActiveRecord::Migration[8.1]
  def up
    table = :recording_studio_webhooks_endpoint_tokens
    return unless column_exists?(table, :token)

    remove_column table, :token
  end

  def down
    # Irreversible for data: plaintext tokens cannot be reconstructed from digests.
    table = :recording_studio_webhooks_endpoint_tokens
    return if column_exists?(table, :token)

    add_column table, :token, :string
  end
end
