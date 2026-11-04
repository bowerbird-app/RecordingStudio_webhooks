# frozen_string_literal: true

require "test_helper"

class RemovePlaintextTokenTest < ActiveSupport::TestCase
  TABLE = "recording_studio_webhooks_endpoint_tokens"

  test "backfills digest from plaintext then drops the token column" do
    connection = ActiveRecord::Base.connection
    endpoint = create_endpoint!

    hashed_issuance = endpoint.issue_token!
    hashed_plaintext = hashed_issuance.plaintext_token
    hashed_token = hashed_issuance.endpoint_token
    hashed_digest = hashed_token.digest

    backfill_endpoint = create_endpoint!
    backfill_issuance = backfill_endpoint.issue_token!
    backfill_plaintext = backfill_issuance.plaintext_token
    backfill_token = backfill_issuance.endpoint_token

    restore_token_column!(connection)
    connection.execute(<<~SQL)
      UPDATE #{TABLE}
      SET token = #{connection.quote(hashed_plaintext)}
      WHERE id = #{connection.quote(hashed_token.id)}
    SQL
    connection.execute(<<~SQL)
      UPDATE #{TABLE}
      SET token = #{connection.quote(backfill_plaintext)}, digest = ''
      WHERE id = #{connection.quote(backfill_token.id)}
    SQL

    migrate_up!
    RecordingStudioWebhooks::EndpointToken.reset_column_information

    refute_includes connection.columns(TABLE).map(&:name), "token"
    assert_equal hashed_digest, select_digest(hashed_token.id)
    assert_equal RecordingStudioWebhooks::TokenDigest.digest(backfill_plaintext), select_digest(backfill_token.id)
    assert_equal hashed_token.id, RecordingStudioWebhooks::EndpointToken.authenticate(plaintext: hashed_plaintext).id
    assert_equal backfill_token.id, RecordingStudioWebhooks::EndpointToken.authenticate(plaintext: backfill_plaintext).id
  ensure
    migrate_up! if ActiveRecord::Base.connection.column_exists?(TABLE, :token)
    RecordingStudioWebhooks::EndpointToken.reset_column_information
  end

  private

  def restore_token_column!(connection)
    return if connection.column_exists?(TABLE, :token)

    connection.add_column TABLE, :token, :string
    RecordingStudioWebhooks::EndpointToken.reset_column_information
  end

  def migrate_up!
    return unless ActiveRecord::Base.connection.column_exists?(TABLE, :token)

    load_migration.up
  end

  def load_migration
    path = RecordingStudioWebhooks::Engine.root.join(
      "db/migrate/20261104000000_remove_plaintext_token_from_endpoint_tokens.rb"
    )
    load path.to_s
    RemovePlaintextTokenFromEndpointTokens.new
  end

  def select_digest(id)
    connection = ActiveRecord::Base.connection
    connection.select_value("SELECT digest FROM #{TABLE} WHERE id = #{connection.quote(id)}")
  end

  def create_endpoint!
    user = User.find_or_create_by!(email: "admin@admin.com") do |record|
      record.password = "Password123!"
      record.password_confirmation = "Password123!"
    end
    workspace = Workspace.create!(name: "Migration #{SecureRandom.hex(4)}")
    recording = RecordingStudio.root_recording_for(workspace)
    result = RecordingStudioAccessible.bootstrap_owner_access!(recording: recording, actor: user)
    raise result.error if result.failure?

    RecordingStudioWebhooks::EndpointLifecycle.create!(
      endpoint: RecordingStudioWebhooks::Endpoint.new(
        recording_studio_recording_id: recording.id,
        label: "Migration endpoint",
        provider_name: "demo",
        identity: {},
        metadata: {},
        policy_overrides: {}
      ),
      actor: user
    )
  end
end
