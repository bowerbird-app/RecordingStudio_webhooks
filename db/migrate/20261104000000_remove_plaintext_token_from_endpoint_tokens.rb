# frozen_string_literal: true

class RemovePlaintextTokenFromEndpointTokens < ActiveRecord::Migration[8.1]
  def up
    table = :recording_studio_webhooks_endpoint_tokens
    return unless column_exists?(table, :token)

    say_with_time "backfill missing endpoint token digests from plaintext" do
      select_all("SELECT id, token, digest FROM #{table}").each do |row|
        next if row["digest"].present?

        plaintext = row["token"].to_s
        if plaintext.empty?
          raise ActiveRecord::IrreversibleMigration,
                "#{table} #{row['id']} has no digest and no plaintext token to backfill"
        end

        hashed = RecordingStudioWebhooks::TokenDigest.digest(plaintext)
        execute(ActiveRecord::Base.sanitize_sql_array([
                                                        "UPDATE #{table} SET digest = ? WHERE id = ?",
                                                        hashed,
                                                        row["id"]
                                                      ]))
      end

      missing = select_value("SELECT COUNT(*) FROM #{table} WHERE digest IS NULL OR digest = ''")
      if missing.to_i.positive?
        raise ActiveRecord::IrreversibleMigration,
              "#{missing} #{table} rows still have no digest"
      end
    end

    remove_column table, :token
  end

  def down
    # Irreversible for data: plaintext tokens cannot be reconstructed from digests.
    table = :recording_studio_webhooks_endpoint_tokens
    return if column_exists?(table, :token)

    add_column table, :token, :string
  end
end
