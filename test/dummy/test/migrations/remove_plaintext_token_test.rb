# frozen_string_literal: true

require "test_helper"

class RemovePlaintextTokenTest < ActiveSupport::TestCase
  TABLE = "recording_studio_webhooks_endpoint_tokens"

  test "drops the token column when present and skips when already gone" do
    connection = ActiveRecord::Base.connection
    endpoint, user = create_endpoint!
    issuance = endpoint.issue_token!(actor: user)
    plaintext = issuance.plaintext_token
    token = issuance.endpoint_token
    digest = token.digest

    restore_token_column!(connection)
    connection.execute(<<~SQL)
      UPDATE #{TABLE}
      SET token = #{connection.quote(plaintext)}
      WHERE id = #{connection.quote(token.id)}
    SQL

    migrate_up!
    RecordingStudioWebhooks::EndpointToken.reset_column_information

    refute_includes connection.columns(TABLE).map(&:name), "token"
    assert_equal digest, select_digest(token.id)
    assert_equal token.id, RecordingStudioWebhooks::EndpointToken.authenticate(plaintext: plaintext).id

    migrate_up!
    refute_includes connection.columns(TABLE).map(&:name), "token"
  ensure
    migrate_up! if ActiveRecord::Base.connection.column_exists?(TABLE, :token)
    RecordingStudioWebhooks::EndpointToken.reset_column_information
  end

  test "down re-adds an empty token column" do
    connection = ActiveRecord::Base.connection
    migrate_up! if connection.column_exists?(TABLE, :token)

    load_migration.down
    RecordingStudioWebhooks::EndpointToken.reset_column_information

    assert_includes connection.columns(TABLE).map(&:name), "token"
    assert(connection.select_values("SELECT token FROM #{TABLE}").all?(&:blank?))
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

    endpoint = RecordingStudioWebhooks::EndpointLifecycle.create!(
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
    [endpoint, user]
  end
end
