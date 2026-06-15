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

ActiveRecord::Schema[8.1].define(version: 2026_06_15_190836) do
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

  add_foreign_key "sessions", "users"
end
