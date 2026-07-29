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

ActiveRecord::Schema[8.1].define(version: 2026_07_29_120000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"

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
    t.index ["recording_id", "idempotency_key"], name: "index_recording_studio_events_on_recording_and_idempotency_key", unique: true, where: "(idempotency_key IS NOT NULL)"
    t.index ["recording_id"], name: "index_recording_studio_events_on_recording_id"
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

  create_table "recording_studio_webhooks_action_plans", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["inbound_event_id", "action_name"], name: "index_rsw_plans_on_event_and_action", unique: true
    t.index ["inbound_event_id", "execution_position"], name: "index_rsw_plans_on_event_and_position", unique: true
    t.index ["inbound_event_id"], name: "index_rsw_plans_on_event_id"
    t.index ["status", "next_attempt_at"], name: "index_rsw_plans_on_status_and_next_attempt"
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
    t.datetime "updated_at", null: false
    t.index ["digest"], name: "index_recording_studio_webhooks_endpoint_tokens_on_digest", unique: true
    t.index ["endpoint_id", "active_at"], name: "index_rsw_tokens_on_endpoint_and_active_at"
    t.index ["endpoint_id"], name: "index_recording_studio_webhooks_endpoint_tokens_on_endpoint_id"
    t.index ["endpoint_id"], name: "index_rsw_tokens_one_unrevoked_per_endpoint", unique: true, where: "(revoked_at IS NULL)"
  end

  create_table "recording_studio_webhooks_endpoints", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "enabled", default: true, null: false
    t.jsonb "identity", default: {}, null: false
    t.string "identity_key", null: false
    t.string "label", null: false
    t.jsonb "metadata", default: {}, null: false
    t.jsonb "policy_overrides", default: {}, null: false
    t.string "provider_name", null: false
    t.uuid "recording_studio_recording_id", null: false
    t.datetime "updated_at", null: false
    t.index ["provider_name", "identity_key"], name: "index_rsw_endpoints_on_provider_and_identity", unique: true
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

  add_foreign_key "recording_studio_events", "recording_studio_recordings", column: "recording_id"
  add_foreign_key "recording_studio_recordings", "recording_studio_recordings", column: "parent_recording_id"
  add_foreign_key "recording_studio_recordings", "recording_studio_recordings", column: "root_recording_id"
  add_foreign_key "recording_studio_webhooks_action_plans", "recording_studio_webhooks_inbound_events", column: "inbound_event_id"
  add_foreign_key "recording_studio_webhooks_endpoint_tokens", "recording_studio_webhooks_endpoints", column: "endpoint_id"
  add_foreign_key "recording_studio_webhooks_endpoints", "recording_studio_recordings"
  add_foreign_key "recording_studio_webhooks_inbound_events", "recording_studio_webhooks_endpoint_tokens", column: "endpoint_token_id"
  add_foreign_key "recording_studio_webhooks_inbound_events", "recording_studio_webhooks_endpoints", column: "endpoint_id"
end
