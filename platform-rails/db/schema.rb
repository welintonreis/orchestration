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

ActiveRecord::Schema[8.1].define(version: 2026_06_15_202111) do
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

  create_table "environments", force: :cascade do |t|
    t.boolean "active", default: false, null: false
    t.datetime "created_at", null: false
    t.string "endpoint", default: "unix:///var/run/docker.sock", null: false
    t.string "endpoint_type", default: "unix", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_environments_on_name", unique: true
  end

  create_table "git_connections", force: :cascade do |t|
    t.string "auth_type", default: "none"
    t.string "branch", default: "main"
    t.datetime "created_at", null: false
    t.string "last_commit_sha"
    t.datetime "last_pulled_at"
    t.string "name", null: false
    t.string "repo_url", null: false
    t.text "ssh_key_ciphertext"
    t.string "token_ciphertext"
    t.datetime "updated_at", null: false
    t.string "username"
    t.index ["name"], name: "index_git_connections_on_name", unique: true
  end

  create_table "git_stacks", force: :cascade do |t|
    t.boolean "auto_update", default: false
    t.string "compose_file", default: "docker-compose.yml"
    t.datetime "created_at", null: false
    t.string "deploy_mode", default: "swarm_stack"
    t.integer "environment_id", null: false
    t.integer "git_connection_id", null: false
    t.text "last_deploy_output"
    t.datetime "last_deployed_at"
    t.string "name", null: false
    t.integer "poll_interval", default: 300
    t.string "status", default: "idle"
    t.datetime "updated_at", null: false
    t.string "webhook_token"
    t.index ["environment_id"], name: "index_git_stacks_on_environment_id"
    t.index ["git_connection_id"], name: "index_git_stacks_on_git_connection_id"
  end

  create_table "host_metrics", force: :cascade do |t|
    t.float "cpu_percent", null: false
    t.datetime "created_at", null: false
    t.float "disk_percent", null: false
    t.float "load_15m", null: false
    t.float "load_1m", null: false
    t.float "load_5m", null: false
    t.float "ram_percent", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_host_metrics_on_created_at"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.string "role"
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "git_stacks", "environments"
  add_foreign_key "git_stacks", "git_connections"
  add_foreign_key "sessions", "users"
end
