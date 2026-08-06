# frozen_string_literal: true

class AddTokenToEndpointTokens < ActiveRecord::Migration[8.1]
  def change
    add_column :recording_studio_webhooks_endpoint_tokens, :token, :string
  end
end
