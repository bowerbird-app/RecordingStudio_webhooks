# frozen_string_literal: true

# db/migrate/20260728000000_create_recording_studio_webhooks_tables.rb
module RecordingStudioWebhooks
  class CreateRecordingStudioWebhooksCoreTables < ActiveRecord::Migration[8.1]
    def change
      create_table :recording_studio_webhook_endpoints, id: :uuid do |t|
      t.string :provider_name, null: false
      t.boolean :enabled, null: false, default: true
      t.jsonb :policy_overrides, null: false, default: {}
      t.jsonb :event_policies, null: false, default: []
      t.jsonb :metadata, null: false, default: {}
      t.datetime :created_at, null: false
      end
      add_index :recording_studio_webhook_endpoints, :provider_name

      create_table :recording_studio_webhook_endpoint_tokens, id: :uuid do |t|
      t.string :digest, null: false
      t.string :prefix, null: false
      t.boolean :enabled, null: false, default: true
      t.datetime :active_at, null: false
      t.datetime :expires_at
      t.jsonb :metadata, null: false, default: {}
      t.datetime :created_at, null: false
      end
      add_index :recording_studio_webhook_endpoint_tokens, :digest, unique: true
      add_index :recording_studio_webhook_endpoint_tokens, %i[enabled active_at expires_at],
        name: "index_rswh_token_snapshots_on_availability"

      create_table :recording_studio_incoming_webhook_logs, id: :uuid do |t|
      t.references :endpoint_recording,
        type: :uuid,
        null: false,
        foreign_key: { to_table: :recording_studio_recordings }
      t.references :endpoint_token_recording,
        type: :uuid,
        null: false,
        foreign_key: { to_table: :recording_studio_recordings }
      t.references :endpoint_snapshot,
        type: :uuid,
        null: false,
        foreign_key: { to_table: :recording_studio_webhook_endpoints }
      t.references :endpoint_token_snapshot,
        type: :uuid,
        null: false,
        foreign_key: { to_table: :recording_studio_webhook_endpoint_tokens }
      t.string :provider_name, null: false
      t.string :event_type, null: false
      t.string :provider_event_id, null: false
      t.string :payload_digest, null: false
      t.jsonb :redacted_payload, null: false, default: {}
      t.jsonb :provenance, null: false, default: {}
      t.string :policy_source, null: false
      t.string :policy_pattern, null: false
      t.string :execution_mode, null: false
      t.string :policy_fingerprint, null: false
      t.string :provider_definition_source, null: false
      t.string :provider_definition_fingerprint, null: false
      t.string :status, null: false, default: "accepted"
      t.datetime :accepted_at, null: false
      t.timestamps
      end
      add_index :recording_studio_incoming_webhook_logs,
      %i[endpoint_recording_id provider_event_id],
      unique: true,
      name: "index_rswh_logs_on_endpoint_recording_and_provider_event"
      add_index :recording_studio_incoming_webhook_logs,
      %i[provider_name event_type accepted_at],
      name: "index_rswh_logs_on_provider_event_and_accepted_at"

      create_table :recording_studio_webhook_action_attempts, id: :uuid do |t|
      t.references :incoming_webhook_log,
        type: :uuid,
        null: false,
        foreign_key: { to_table: :recording_studio_incoming_webhook_logs }
      t.string :action_key, null: false
      t.integer :sequence, null: false
      t.integer :attempt_number, null: false
      t.string :status, null: false, default: "pending"
      t.jsonb :matching_provenance, null: false, default: {}
      t.string :matching_fingerprint, null: false
      t.string :action_source, null: false
      t.string :action_fingerprint, null: false
      t.string :policy_source, null: false
      t.string :policy_pattern, null: false
      t.string :execution_mode, null: false
      t.string :policy_fingerprint, null: false
      t.integer :max_retries, null: false, default: 0
      t.integer :retry_backoff, null: false, default: 1
      t.integer :max_retry_backoff, null: false, default: 1
      t.integer :dispatch_failures, null: false, default: 0
      t.string :backend
      t.string :job_id
      t.string :manual_actor_type
      t.uuid :manual_actor_id
      t.datetime :queued_at
      t.datetime :started_at
      t.datetime :completed_at
      t.datetime :next_attempt_at
      t.string :last_error
      t.timestamps
      end
      add_index :recording_studio_webhook_action_attempts,
      %i[incoming_webhook_log_id action_key attempt_number],
      unique: true,
      name: "index_rswh_attempts_on_log_action_and_attempt_number"
      add_index :recording_studio_webhook_action_attempts,
      %i[status next_attempt_at],
      name: "index_rswh_attempts_on_status_and_next_attempt"
      add_index :recording_studio_webhook_action_attempts,
      %i[incoming_webhook_log_id sequence],
      name: "index_rswh_attempts_on_log_and_sequence"
      add_index :recording_studio_webhook_action_attempts,
      %i[manual_actor_type manual_actor_id],
      name: "index_rswh_attempts_on_manual_actor"
    end
  end
end
