# frozen_string_literal: true

# The version tracks db/cache_migrate, which is what actually creates these
# tables (IMP-4c5c53574683): on this platform every production config shares one
# physical database, so DatabaseTasks#initialize_database always finds
# schema_migrations already present by the time it reaches the cache config and
# never loads this dump. It stays live only for a deployment that splits the
# cache database off (DATABASE_NAME_CACHE) — and there the version MUST equal the
# latest cache migration, or loading this dump would leave that migration pending
# and the table would be created twice. spec/db/solid_cache_schema_delivery_spec.rb
# pins both halves.
ActiveRecord::Schema[7.2].define(version: 2026_09_04_175500) do
  create_table "solid_cache_entries", force: :cascade do |t|
    t.binary "key", limit: 1024, null: false
    t.binary "value", limit: 536870912, null: false
    t.datetime "created_at", null: false
    t.integer "key_hash", limit: 8, null: false
    t.integer "byte_size", limit: 4, null: false
    t.index ["byte_size"], name: "index_solid_cache_entries_on_byte_size"
    t.index ["key_hash", "byte_size"], name: "index_solid_cache_entries_on_key_hash_and_byte_size"
    t.index ["key_hash"], name: "index_solid_cache_entries_on_key_hash", unique: true
  end
end
