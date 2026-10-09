# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_10_09_120000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"

  create_table "admin_roots", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", default: "Admin", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "folders", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.datetime "updated_at", null: false
  end

  create_table "pages", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "title"
    t.datetime "updated_at", null: false
  end

  create_table "recording_studio_access_invitations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "recording_id", null: false
    t.string "email", null: false
    t.string "role", null: false
    t.string "token_digest", limit: 64, null: false
    t.string "manager_actor_type", null: false
    t.uuid "manager_actor_id", null: false
    t.string "accepted_by_actor_type"
    t.uuid "accepted_by_actor_id"
    t.datetime "expires_at", null: false
    t.datetime "last_sent_at", null: false
    t.datetime "accepted_at"
    t.datetime "revoked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["recording_id", "email"], name: "idx_rs_access_invitations_one_active", unique: true, where: "((accepted_at IS NULL) AND (revoked_at IS NULL))"
    t.index ["recording_id"], name: "index_recording_studio_access_invitations_on_recording_id"
    t.index ["token_digest"], name: "idx_rs_access_invitations_token_digest", unique: true
    t.check_constraint "accepted_at IS NULL OR revoked_at IS NULL", name: "access_invitations_not_accepted_and_revoked"
  end

  create_table "recording_studio_accesses", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "actor_id", null: false
    t.string "actor_type", null: false
    t.datetime "created_at", null: false
    t.string "role", default: "view", null: false
    t.uuid "depends_on_recording_id"
    t.index ["actor_type", "actor_id", "role"], name: "index_recording_studio_accesses_on_actor_and_role"
    t.index ["actor_type", "actor_id"], name: "index_recording_studio_accesses_on_actor"
    t.index ["depends_on_recording_id"], name: "index_recording_studio_accesses_on_depends_on_recording_id"
  end

  create_table "recording_studio_api_admin_apis", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "key", null: false
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_recording_studio_api_admin_apis_on_key", unique: true
  end

  create_table "recording_studio_api_api_access_tokens", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "api_credential_id", null: false
    t.string "token_digest", null: false
    t.string "token_prefix", null: false
    t.datetime "expires_at", null: false
    t.datetime "last_used_at"
    t.datetime "revoked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["api_credential_id"], name: "idx_on_api_credential_id_89874cbf51"
    t.index ["expires_at"], name: "index_recording_studio_api_api_access_tokens_on_expires_at"
    t.index ["token_digest"], name: "index_recording_studio_api_api_access_tokens_on_token_digest", unique: true
  end

  create_table "recording_studio_api_api_clients", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "access_recording_id"
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "api_key", default: "public", null: false
    t.index ["access_recording_id"], name: "index_recording_studio_api_api_clients_on_access_recording_id", unique: true
    t.index ["api_key"], name: "index_recording_studio_api_api_clients_on_api_key"
  end

  create_table "recording_studio_api_api_credentials", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "api_client_id", null: false
    t.uuid "access_recording_id", null: false
    t.string "token_public_id", null: false
    t.string "token_digest", null: false
    t.string "token_prefix", null: false
    t.datetime "expires_at"
    t.datetime "last_used_at"
    t.datetime "revoked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["access_recording_id"], name: "idx_on_access_recording_id_103368144f"
    t.index ["api_client_id"], name: "index_recording_studio_api_api_credentials_on_api_client_id"
    t.index ["api_client_id"], name: "index_recording_studio_api_credentials_on_active_client", unique: true, where: "(revoked_at IS NULL)"
    t.index ["token_digest"], name: "index_recording_studio_api_api_credentials_on_token_digest", unique: true
    t.index ["token_public_id"], name: "index_recording_studio_api_api_credentials_on_token_public_id", unique: true
  end

  create_table "recording_studio_api_api_daily_latency_histogram_buckets", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.date "metric_date", null: false
    t.string "route_name", null: false
    t.string "request_method", null: false
    t.integer "status_class", null: false
    t.integer "upper_bound_ms", null: false
    t.bigint "request_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "api_key", default: "public", null: false
    t.index ["api_key", "metric_date", "route_name", "request_method", "status_class", "upper_bound_ms"], name: "index_rs_api_daily_latency_histogram_on_dimensions", unique: true
    t.index ["metric_date"], name: "idx_on_metric_date_8723beba88"
  end

  create_table "recording_studio_api_api_daily_metrics", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.date "metric_date", null: false
    t.string "route_name", null: false
    t.string "controller_name"
    t.string "action_name"
    t.string "request_method", null: false
    t.integer "status_class", null: false
    t.bigint "request_count", default: 0, null: false
    t.bigint "rate_limited_count", default: 0, null: false
    t.bigint "client_error_count", default: 0, null: false
    t.bigint "server_error_count", default: 0, null: false
    t.bigint "duration_count", default: 0, null: false
    t.bigint "duration_sum_ms", default: 0, null: false
    t.integer "duration_max_ms", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "api_key", default: "public", null: false
    t.index ["api_key", "metric_date", "route_name", "request_method", "status_class"], name: "index_rs_api_daily_metrics_on_dimensions", unique: true
    t.index ["metric_date"], name: "index_recording_studio_api_api_daily_metrics_on_metric_date"
  end

  create_table "recording_studio_api_api_request_logs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "occurred_at", null: false
    t.string "request_id"
    t.string "request_method", null: false
    t.string "request_path", null: false
    t.string "route_name"
    t.string "controller_name"
    t.string "action_name"
    t.integer "status_code", null: false
    t.integer "duration_ms", null: false
    t.boolean "rate_limited", default: false, null: false
    t.uuid "api_client_id"
    t.uuid "api_credential_id"
    t.uuid "access_recording_id"
    t.uuid "root_recording_id"
    t.string "remote_ip"
    t.string "user_agent"
    t.string "error_class"
    t.string "error_message"
    t.jsonb "request_params", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "api_key", default: "public", null: false
    t.index ["api_client_id", "occurred_at"], name: "index_rs_api_request_logs_on_client_and_time"
    t.index ["api_credential_id", "occurred_at"], name: "index_rs_api_request_logs_on_credential_and_time"
    t.index ["api_key", "occurred_at"], name: "index_rs_api_request_logs_on_api_and_time"
    t.index ["occurred_at"], name: "index_recording_studio_api_api_request_logs_on_occurred_at"
    t.index ["request_id"], name: "index_recording_studio_api_api_request_logs_on_request_id"
    t.index ["request_path"], name: "index_recording_studio_api_api_request_logs_on_request_path"
    t.index ["status_code"], name: "index_recording_studio_api_api_request_logs_on_status_code"
  end

  create_table "recording_studio_api_api_settings", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "key", null: false
    t.boolean "api_access_enabled", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "runtime_overrides", default: {}, null: false
    t.index ["key"], name: "index_recording_studio_api_api_settings_on_key", unique: true
  end

  create_table "recording_studio_events", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "action", null: false
    t.uuid "actor_id"
    t.string "actor_type"
    t.datetime "created_at", null: false
    t.string "idempotency_key"
    t.uuid "impersonator_id"
    t.string "impersonator_type"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "occurred_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.uuid "previous_recordable_id"
    t.string "previous_recordable_type"
    t.uuid "recordable_id", null: false
    t.string "recordable_type", null: false
    t.uuid "recording_id", null: false
    t.index ["action", "occurred_at"], name: "index_rs_events_on_action_and_occurred_at"
    t.index ["actor_type", "actor_id", "occurred_at"], name: "index_rs_events_on_actor_and_occurred_at"
    t.index ["recording_id", "idempotency_key"], name: "index_recording_studio_events_on_recording_and_idempotency_key", unique: true, where: "(idempotency_key IS NOT NULL)"
    t.index ["recording_id", "occurred_at", "created_at"], name: "index_rs_events_on_recording_and_timeline", order: { occurred_at: :desc, created_at: :desc }
    t.index ["recording_id"], name: "index_recording_studio_events_on_recording_id"
  end

  create_table "recording_studio_metrics_pages", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "workspace_id", null: false
    t.string "title", null: false
    t.string "slug", null: false
    t.jsonb "content", default: {}, null: false
    t.boolean "published", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["published"], name: "index_recording_studio_metrics_pages_on_published"
    t.index ["workspace_id", "slug"], name: "index_recording_studio_metrics_pages_on_workspace_id_and_slug", unique: true
    t.index ["workspace_id"], name: "index_recording_studio_metrics_pages_on_workspace_id"
  end

  create_table "recording_studio_recordings", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.uuid "parent_recording_id"
    t.uuid "recordable_id", null: false
    t.string "recordable_type", null: false
    t.uuid "root_recording_id"
    t.datetime "trashed_at"
    t.datetime "updated_at", null: false
    t.index ["parent_recording_id"], name: "index_recording_studio_recordings_on_parent_recording_id"
    t.index ["recordable_type", "recordable_id", "parent_recording_id", "trashed_at"], name: "index_recording_studio_recordings_on_recordable_parent_trashed"
    t.index ["recordable_type", "recordable_id"], name: "index_recording_studio_recordings_on_recordable"
    t.index ["recordable_type", "recordable_id"], name: "index_rs_unique_root_recording_per_recordable", unique: true, where: "(parent_recording_id IS NULL)"
    t.index ["root_recording_id", "parent_recording_id"], name: "index_rs_recordings_on_root_and_parent"
    t.index ["root_recording_id", "recordable_type", "recordable_id"], name: "index_rs_recordings_on_root_and_recordable"
    t.index ["root_recording_id"], name: "index_rs_recordings_on_root_recording"
  end

  create_table "recording_studio_root_switchable_selections", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "actor_id"
    t.string "actor_type"
    t.datetime "created_at", null: false
    t.string "device_browser"
    t.string "device_key", null: false
    t.string "device_label"
    t.string "device_platform"
    t.string "device_type"
    t.datetime "last_used_at", null: false
    t.uuid "root_recording_id", null: false
    t.string "scope_key", null: false
    t.datetime "updated_at", null: false
    t.text "user_agent"
    t.index ["actor_type", "actor_id", "device_key", "scope_key"], name: "idx_rs_root_switchable_actor_device_scope", unique: true, where: "(actor_id IS NOT NULL)"
    t.index ["device_key", "scope_key"], name: "idx_rs_root_switchable_anonymous_device_scope", unique: true, where: "(actor_id IS NULL)"
    t.index ["root_recording_id"], name: "idx_rs_root_switchable_root_recording"
  end

  create_table "recording_studio_webhooks_action_attempts", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "action_name", null: false
    t.jsonb "action_snapshot", default: {}, null: false
    t.jsonb "attempt_history", default: [], null: false
    t.integer "attempts", default: 0, null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.jsonb "endpoint_snapshot", default: {}, null: false
    t.integer "execution_position", null: false
    t.uuid "inbound_event_id", null: false
    t.string "last_error"
    t.datetime "next_attempt_at"
    t.jsonb "policy_snapshot", default: {}, null: false
    t.datetime "queued_at"
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.jsonb "token_snapshot", default: {}, null: false
    t.datetime "updated_at", null: false
    t.index ["inbound_event_id", "action_name"], name: "index_rsw_attempts_on_event_and_action", unique: true
    t.index ["inbound_event_id", "execution_position"], name: "index_rsw_attempts_on_event_and_position", unique: true
    t.index ["inbound_event_id"], name: "index_rsw_attempts_on_event_id"
    t.index ["status", "next_attempt_at"], name: "index_rsw_attempts_on_status_and_next_attempt"
  end

  create_table "recording_studio_webhooks_endpoint_tokens", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "active_at", null: false
    t.datetime "created_at", null: false
    t.string "digest", null: false
    t.uuid "endpoint_id", null: false
    t.datetime "expires_at"
    t.jsonb "metadata", default: {}, null: false
    t.string "prefix", null: false
    t.datetime "revoked_at"
    t.string "revoked_by_actor_id"
    t.string "token"
    t.datetime "updated_at", null: false
    t.index ["digest"], name: "index_recording_studio_webhooks_endpoint_tokens_on_digest"
    t.index ["endpoint_id", "active_at"], name: "index_rsw_tokens_on_endpoint_and_active_at"
    t.index ["endpoint_id"], name: "index_recording_studio_webhooks_endpoint_tokens_on_endpoint_id"
  end

  create_table "recording_studio_webhooks_endpoints", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "enabled", default: true, null: false
    t.jsonb "identity", default: {}, null: false
    t.string "label", null: false
    t.jsonb "metadata", default: {}, null: false
    t.jsonb "policy_overrides", default: {}, null: false
    t.string "provider_name", null: false
    t.uuid "recording_studio_recording_id", null: false
    t.datetime "updated_at", null: false
    t.index ["provider_name", "recording_studio_recording_id"], name: "index_rsw_endpoints_on_provider_and_recording"
    t.index ["provider_name"], name: "index_recording_studio_webhooks_endpoints_on_provider_name"
    t.index ["recording_studio_recording_id"], name: "index_rsw_endpoints_on_recording_id"
  end

  create_table "recording_studio_webhooks_inbound_events", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "deduplication_key", null: false
    t.uuid "endpoint_id", null: false
    t.jsonb "endpoint_snapshot", default: {}, null: false
    t.uuid "endpoint_token_id", null: false
    t.string "event_type", null: false
    t.jsonb "payload", default: {}, null: false
    t.string "payload_digest", null: false
    t.jsonb "policy_snapshot", default: {}, null: false
    t.jsonb "provenance", default: {}, null: false
    t.string "provider_event_id"
    t.string "provider_name", null: false
    t.datetime "received_at", null: false
    t.string "status", default: "accepted", null: false
    t.jsonb "token_snapshot", default: {}, null: false
    t.datetime "updated_at", null: false
    t.index ["endpoint_id", "deduplication_key"], name: "index_rsw_events_on_endpoint_and_deduplication", unique: true
    t.index ["endpoint_id"], name: "index_recording_studio_webhooks_inbound_events_on_endpoint_id"
    t.index ["endpoint_token_id"], name: "index_rsw_events_on_endpoint_token_id"
    t.index ["provider_name", "event_type", "received_at"], name: "index_rsw_events_on_provider_event_received"
  end

  create_table "users", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  create_table "workspaces", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.datetime "updated_at", null: false
  end

  add_foreign_key "recording_studio_access_invitations", "recording_studio_recordings", column: "recording_id"
  add_foreign_key "recording_studio_api_api_access_tokens", "recording_studio_api_api_credentials", column: "api_credential_id"
  add_foreign_key "recording_studio_api_api_credentials", "recording_studio_api_api_clients", column: "api_client_id"
  add_foreign_key "recording_studio_events", "recording_studio_recordings", column: "recording_id"
  add_foreign_key "recording_studio_recordings", "recording_studio_recordings", column: "parent_recording_id"
  add_foreign_key "recording_studio_recordings", "recording_studio_recordings", column: "root_recording_id"
  add_foreign_key "recording_studio_webhooks_action_attempts", "recording_studio_webhooks_inbound_events", column: "inbound_event_id"
  add_foreign_key "recording_studio_webhooks_endpoint_tokens", "recording_studio_webhooks_endpoints", column: "endpoint_id"
  add_foreign_key "recording_studio_webhooks_endpoints", "recording_studio_recordings"
  add_foreign_key "recording_studio_webhooks_inbound_events", "recording_studio_webhooks_endpoint_tokens", column: "endpoint_token_id"
  add_foreign_key "recording_studio_webhooks_inbound_events", "recording_studio_webhooks_endpoints", column: "endpoint_id"
end
