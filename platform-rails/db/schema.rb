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

ActiveRecord::Schema[8.1].define(version: 2026_09_01_100100) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "vector"

  create_table "ai_accounts", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "auth_type", default: "oauth", null: false
    t.datetime "created_at", null: false
    t.string "credential_path"
    t.string "credential_source", default: "inline", null: false
    t.text "credentials"
    t.string "display_name"
    t.string "email"
    t.string "last_error"
    t.datetime "last_error_at"
    t.datetime "last_used_at"
    t.string "name"
    t.integer "priority", default: 1
    t.string "provider", null: false
    t.json "provider_data", default: {}
    t.string "test_status"
    t.datetime "updated_at", null: false
    t.index ["provider", "active"], name: "index_ai_accounts_on_provider_and_active"
    t.index ["provider"], name: "index_ai_accounts_on_provider"
  end

  create_table "ai_quota_snapshots", force: :cascade do |t|
    t.integer "ai_account_id", null: false
    t.datetime "captured_at", null: false
    t.datetime "created_at", null: false
    t.string "model_key"
    t.string "quota_name", null: false
    t.integer "remaining_pct"
    t.datetime "reset_at"
    t.integer "total"
    t.integer "used"
    t.index ["ai_account_id", "quota_name", "captured_at"], name: "index_ai_quota_snapshots_on_account_quota_time"
    t.index ["ai_account_id"], name: "index_ai_quota_snapshots_on_ai_account_id"
  end

  create_table "alerts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "level", null: false
    t.text "message", null: false
    t.datetime "read_at"
    t.string "resource", null: false
    t.datetime "updated_at", null: false
    t.index ["level"], name: "index_alerts_on_level"
    t.index ["read_at"], name: "index_alerts_on_read_at"
  end

  create_table "app_assets", force: :cascade do |t|
    t.string "content_type"
    t.datetime "created_at", null: false
    t.binary "data"
    t.string "key"
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_app_assets_on_key", unique: true
  end

  create_table "app_settings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "key"
    t.datetime "updated_at", null: false
    t.text "value"
    t.index ["key"], name: "index_app_settings_on_key", unique: true
  end

  create_table "app_templates", force: :cascade do |t|
    t.boolean "built_in", default: false, null: false
    t.text "compose_yaml", null: false
    t.datetime "created_at", null: false
    t.string "description"
    t.string "icon", default: "box"
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.json "variables", default: {}, null: false
    t.index ["name"], name: "index_app_templates_on_name", unique: true
  end

  create_table "audit_logs", force: :cascade do |t|
    t.string "action", null: false
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.json "metadata", default: {}
    t.string "target_id"
    t.string "target_type"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["action"], name: "index_audit_logs_on_action"
    t.index ["created_at"], name: "index_audit_logs_on_created_at"
    t.index ["user_id"], name: "index_audit_logs_on_user_id"
  end

  create_table "edge_commands", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "edge_node_id", null: false
    t.datetime "expires_at", null: false
    t.string "kind", null: false
    t.text "payload"
    t.text "result"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["edge_node_id", "status"], name: "index_edge_commands_on_edge_node_id_and_status"
    t.index ["edge_node_id"], name: "index_edge_commands_on_edge_node_id"
  end

  create_table "edge_nodes", force: :cascade do |t|
    t.string "agent_version"
    t.string "arch"
    t.datetime "created_at", null: false
    t.integer "environment_id", null: false
    t.datetime "last_seen_at"
    t.string "name", null: false
    t.string "os"
    t.datetime "revoked_at"
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.string "uuid", null: false
    t.index ["environment_id"], name: "index_edge_nodes_on_environment_id"
    t.index ["token_digest"], name: "index_edge_nodes_on_token_digest", unique: true
    t.index ["uuid"], name: "index_edge_nodes_on_uuid", unique: true
  end

  create_table "environment_group_memberships", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "environment_group_id", null: false
    t.integer "environment_id", null: false
    t.datetime "updated_at", null: false
    t.index ["environment_group_id"], name: "index_environment_group_memberships_on_environment_group_id"
    t.index ["environment_id"], name: "index_environment_group_memberships_on_environment_id"
  end

  create_table "environment_groups", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name"
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_environment_groups_on_name", unique: true
  end

  create_table "environment_registries", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "encrypted_password"
    t.integer "environment_id", null: false
    t.datetime "updated_at", null: false
    t.string "url"
    t.string "username"
    t.index ["environment_id"], name: "index_environment_registries_on_environment_id"
  end

  create_table "environment_tag_assignments", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "environment_id", null: false
    t.integer "environment_tag_id", null: false
    t.datetime "updated_at", null: false
    t.index ["environment_id"], name: "index_environment_tag_assignments_on_environment_id"
    t.index ["environment_tag_id"], name: "index_environment_tag_assignments_on_environment_tag_id"
  end

  create_table "environment_tags", force: :cascade do |t|
    t.string "color"
    t.datetime "created_at", null: false
    t.string "name"
    t.datetime "updated_at", null: false
  end

  create_table "environments", force: :cascade do |t|
    t.boolean "active", default: false, null: false
    t.datetime "created_at", null: false
    t.string "endpoint", default: "unix:///var/run/docker.sock", null: false
    t.string "endpoint_type", default: "unix", null: false
    t.string "kube_api_url"
    t.text "kube_ca_cert"
    t.text "kube_client_cert_ciphertext"
    t.text "kube_client_key_ciphertext"
    t.text "kube_token_ciphertext"
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_environments_on_name", unique: true
  end

  create_table "git_credentials", force: :cascade do |t|
    t.string "auth_type", default: "token", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.string "site", null: false
    t.text "ssh_key_ciphertext"
    t.string "token_ciphertext"
    t.datetime "updated_at", null: false
    t.string "username"
    t.index ["name"], name: "index_git_credentials_on_name", unique: true
  end

  create_table "git_stack_revisions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "deploy_output"
    t.datetime "deployed_at"
    t.integer "git_stack_id", null: false
    t.text "image_digests"
    t.text "normalized_compose"
    t.string "result", default: "success"
    t.string "sha"
    t.datetime "updated_at", null: false
    t.index ["git_stack_id"], name: "index_git_stack_revisions_on_git_stack_id"
  end

  create_table "git_stacks", force: :cascade do |t|
    t.boolean "auto_update", default: false
    t.string "branch", default: "main"
    t.boolean "ci_check_enabled", default: false
    t.string "ci_gitlab_url"
    t.string "ci_project_id"
    t.string "ci_token_ciphertext"
    t.string "compose_file", default: "docker-compose.yml"
    t.datetime "created_at", null: false
    t.string "deploy_mode", default: "swarm_stack"
    t.text "drift_detail"
    t.text "env_content"
    t.integer "environment_id", null: false
    t.integer "git_credential_id"
    t.string "health", default: "unknown"
    t.string "last_commit_sha"
    t.text "last_deploy_output"
    t.datetime "last_deployed_at"
    t.datetime "last_drift_at"
    t.datetime "last_pulled_at"
    t.string "name", null: false
    t.integer "poll_interval", default: 300
    t.string "post_sync_cmd"
    t.string "pre_sync_cmd"
    t.string "repo_url"
    t.boolean "self_heal", default: false
    t.string "source_type", default: "git", null: false
    t.string "status", default: "idle"
    t.string "sync_status", default: "unknown"
    t.string "sync_window"
    t.integer "target_group_id"
    t.string "token_ciphertext"
    t.datetime "updated_at", null: false
    t.string "username"
    t.string "uuid", null: false
    t.string "webhook_token"
    t.text "yaml_content"
    t.index ["environment_id"], name: "index_git_stacks_on_environment_id"
    t.index ["git_credential_id"], name: "index_git_stacks_on_git_credential_id"
    t.index ["target_group_id"], name: "index_git_stacks_on_target_group_id"
    t.index ["uuid"], name: "index_git_stacks_on_uuid", unique: true
  end

  create_table "host_metrics", force: :cascade do |t|
    t.float "cpu_percent", null: false
    t.datetime "created_at", null: false
    t.float "disk_percent", null: false
    t.integer "edge_node_id"
    t.float "load_15m", null: false
    t.float "load_1m", null: false
    t.float "load_5m", null: false
    t.float "ram_percent", null: false
    t.float "swap_percent", default: 0.0, null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_host_metrics_on_created_at"
    t.index ["edge_node_id"], name: "index_host_metrics_on_edge_node_id"
  end

  create_table "sessions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "shared_credentials", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "credential_type"
    t.text "description"
    t.text "encrypted_secret"
    t.string "name"
    t.datetime "updated_at", null: false
    t.string "username"
  end

  create_table "swarm_registries", force: :cascade do |t|
    t.string "api_type"
    t.datetime "created_at", null: false
    t.string "encrypted_password"
    t.string "name"
    t.boolean "public", default: false, null: false
    t.datetime "updated_at", null: false
    t.string "url"
    t.string "username"
  end

  create_table "team_environment_permissions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "environment_id", null: false
    t.string "role", default: "readonly", null: false
    t.integer "team_id", null: false
    t.datetime "updated_at", null: false
    t.index ["environment_id"], name: "index_team_environment_permissions_on_environment_id"
    t.index ["team_id", "environment_id"], name: "index_team_env_perms_on_team_and_env", unique: true
    t.index ["team_id"], name: "index_team_environment_permissions_on_team_id"
  end

  create_table "team_memberships", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "role"
    t.integer "team_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["team_id"], name: "index_team_memberships_on_team_id"
    t.index ["user_id"], name: "index_team_memberships_on_user_id"
  end

  create_table "teams", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name"
    t.datetime "updated_at", null: false
  end

  create_table "users", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "avatar_content_type"
    t.binary "avatar_data"
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.string "role"
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  create_table "vps_hosts", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "auth_method", default: "password", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.string "host_key_fingerprint"
    t.string "hostname", null: false
    t.datetime "last_connected_at"
    t.string "name", null: false
    t.integer "port", default: 22, null: false
    t.bigint "shared_credential_id"
    t.datetime "updated_at", null: false
    t.string "username", null: false
    t.index ["name"], name: "index_vps_hosts_on_name", unique: true
    t.index ["shared_credential_id"], name: "index_vps_hosts_on_shared_credential_id"
  end

  create_table "vps_terminal_sessions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "ended_at"
    t.text "error_message"
    t.integer "slot", default: 0
    t.datetime "started_at"
    t.string "status", default: "connecting", null: false
    t.integer "terminal_cols"
    t.integer "terminal_rows"
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.uuid "vps_host_id", null: false
    t.index ["token"], name: "index_vps_terminal_sessions_on_token", unique: true
    t.index ["user_id"], name: "index_vps_terminal_sessions_on_user_id"
    t.index ["vps_host_id"], name: "index_vps_terminal_sessions_on_vps_host_id"
  end

  add_foreign_key "ai_quota_snapshots", "ai_accounts"
  add_foreign_key "audit_logs", "users"
  add_foreign_key "edge_commands", "edge_nodes"
  add_foreign_key "edge_nodes", "environments"
  add_foreign_key "environment_group_memberships", "environment_groups"
  add_foreign_key "environment_group_memberships", "environments"
  add_foreign_key "environment_registries", "environments"
  add_foreign_key "environment_tag_assignments", "environment_tags"
  add_foreign_key "environment_tag_assignments", "environments"
  add_foreign_key "git_stack_revisions", "git_stacks"
  add_foreign_key "git_stacks", "environment_groups", column: "target_group_id"
  add_foreign_key "git_stacks", "environments"
  add_foreign_key "host_metrics", "edge_nodes"
  add_foreign_key "sessions", "users"
  add_foreign_key "team_environment_permissions", "environments"
  add_foreign_key "team_environment_permissions", "teams"
  add_foreign_key "team_memberships", "teams"
  add_foreign_key "team_memberships", "users"
  add_foreign_key "vps_hosts", "shared_credentials"
  add_foreign_key "vps_terminal_sessions", "users"
  add_foreign_key "vps_terminal_sessions", "vps_hosts"
end
