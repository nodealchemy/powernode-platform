# frozen_string_literal: true

class ContentCmsBaseline < ActiveRecord::Migration[8.1]
  def change
  create_table "pages", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "author_id", null: false
    t.text "content"
    t.datetime "created_at", null: false
    t.integer "estimated_read_time"
    t.text "excerpt"
    t.boolean "is_public", default: false
    t.text "meta_description"
    t.text "meta_keywords"
    t.string "meta_title", limit: 255
    t.jsonb "metadata", default: {}
    t.datetime "published_at"
    t.text "rendered_content"
    t.text "seo_description"
    t.string "seo_title", limit: 255
    t.string "slug", limit: 255, null: false
    t.string "status", limit: 50, default: "draft"
    t.string "title", limit: 255, null: false
    t.datetime "updated_at", null: false
    t.integer "word_count"
    t.index ["account_id"]
    t.index ["author_id"]
    t.index ["is_public"]
    t.index ["published_at"]
    t.index ["slug"], unique: true
    t.index ["status"]
    t.check_constraint "status::text = ANY (ARRAY['draft'::character varying::text, 'published'::character varying::text, 'archived'::character varying::text])", name: "valid_page_status"
  end

  create_table "shared_prompt_templates", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id"
    t.string "category", null: false
    t.uuid "cloned_from_id"
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.uuid "created_by_id"
    t.text "description"
    t.string "domain", default: "general", null: false
    t.boolean "is_active", default: true, null: false
    t.boolean "is_system", default: false, null: false
    t.jsonb "metadata", default: {}, null: false
    t.jsonb "model_requirements", default: {}, null: false
    t.string "name", null: false
    t.uuid "parent_template_id"
    t.decimal "rating", precision: 3, scale: 2, default: "0.0"
    t.integer "rating_count", default: 0
    t.string "slug", null: false
    t.string "source_key", limit: 255
    t.jsonb "source_snapshot", default: {}, null: false
    t.string "source_version"
    t.datetime "updated_at", null: false
    t.jsonb "variables", default: [], null: false
    t.integer "version", default: 1, null: false
    t.index ["account_id", "category"]
    t.index ["account_id", "domain"]
    t.index ["account_id", "slug"], unique: true, where: "(account_id IS NOT NULL)"
    t.index ["cloned_from_id"]
    t.index ["is_active"]
    t.index ["is_system"]
    t.index ["parent_template_id"]
    t.index ["slug"], unique: true, where: "(account_id IS NULL)", name: "index_shared_prompt_templates_on_slug_global"
    t.index ["source_key"]
  end

  create_table "site_settings", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.string "category", limit: 100
    t.datetime "created_at", null: false
    t.text "description"
    t.boolean "is_public", default: true
    t.string "key", limit: 255, null: false
    t.string "setting_type", limit: 50, default: "string"
    t.datetime "updated_at", null: false
    t.text "value"
    t.index ["category"]
    t.index ["is_public"]
    t.index ["key"], unique: true
    t.index ["setting_type"]
    t.check_constraint "setting_type::text = ANY (ARRAY['string'::character varying::text, 'text'::character varying::text, 'integer'::character varying::text, 'boolean'::character varying::text, 'json'::character varying::text, 'array'::character varying::text])", name: "valid_site_setting_type"
  end

    add_foreign_key "pages", "accounts", column: "account_id"
    add_foreign_key "pages", "users", column: "author_id"
    add_foreign_key "shared_prompt_templates", "accounts", column: "account_id", on_delete: :cascade
    add_foreign_key "shared_prompt_templates", "shared_prompt_templates", column: "parent_template_id", on_delete: :nullify
    add_foreign_key "shared_prompt_templates", "users", column: "created_by_id", on_delete: :nullify
  end
end
