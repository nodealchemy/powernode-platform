# frozen_string_literal: true

class KnowledgeBaseBaseline < ActiveRecord::Migration[8.1]
  def change
  create_table "knowledge_base_article_tags", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "article_id", null: false
    t.datetime "created_at", null: false
    t.uuid "tag_id", null: false
    t.datetime "updated_at", null: false
    t.index ["article_id", "tag_id"], unique: true
    t.index ["tag_id"]
  end

  create_table "knowledge_base_article_views", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "article_id", null: false
    t.datetime "created_at", null: false
    t.string "ip_address", limit: 45
    t.jsonb "metadata", default: {}
    t.boolean "read_to_end", default: false
    t.integer "reading_time_seconds"
    t.string "referrer", limit: 1000
    t.string "session_id", limit: 255
    t.datetime "updated_at", null: false
    t.string "user_agent", limit: 1000
    t.uuid "user_id"
    t.datetime "viewed_at", null: false
    t.index ["article_id", "viewed_at"]
    t.index ["read_to_end"]
    t.index ["session_id"]
    t.index ["user_id"]
    t.index ["viewed_at"]
    t.check_constraint "reading_time_seconds IS NULL OR reading_time_seconds >= 0", name: "valid_kb_reading_time_seconds"
  end

  create_table "knowledge_base_articles", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id"
    t.uuid "author_id"
    t.uuid "category_id", null: false
    t.uuid "cloned_from_id"
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.text "excerpt"
    t.integer "helpful_count", default: 0
    t.decimal "helpfulness_score", precision: 5, scale: 2, default: "0.0"
    t.boolean "is_featured", default: false
    t.boolean "is_public", default: true
    t.uuid "last_edited_by_id"
    t.datetime "last_reviewed_at"
    t.integer "likes_count", default: 0
    t.text "meta_description"
    t.string "meta_title", limit: 255
    t.jsonb "metadata", default: {}
    t.jsonb "model_requirements", default: {}, null: false
    t.integer "not_helpful_count", default: 0
    t.datetime "published_at"
    t.integer "reading_time_minutes"
    t.tsvector "search_vector"
    t.string "slug", limit: 255, null: false
    t.integer "sort_order", default: 0
    t.string "source_key", limit: 255
    t.jsonb "source_snapshot", default: {}, null: false
    t.string "source_version"
    t.string "status", limit: 50, default: "draft"
    t.string "title", limit: 255, null: false
    t.datetime "updated_at", null: false
    t.integer "view_count", default: 0
    t.integer "views_count", default: 0
    t.index ["account_id"]
    t.index ["author_id"]
    t.index ["category_id"]
    t.index ["cloned_from_id"]
    t.index ["helpfulness_score"]
    t.index ["is_featured"]
    t.index ["is_public"]
    t.index ["last_edited_by_id"]
    t.index ["published_at"]
    t.index ["search_vector"], name: "idx_knowledge_base_articles_on_search_vector", using: :gin
    t.index ["slug"], unique: true
    t.index ["source_key"]
    t.index ["status"]
    t.index ["view_count"]
    t.check_constraint "helpful_count >= 0 AND not_helpful_count >= 0", name: "valid_kb_helpful_counts"
    t.check_constraint "helpfulness_score >= 0::numeric AND helpfulness_score <= 100::numeric", name: "valid_kb_helpfulness_score"
    t.check_constraint "reading_time_minutes IS NULL OR reading_time_minutes > 0", name: "valid_kb_reading_time"
    t.check_constraint "status::text = ANY (ARRAY['draft'::character varying::text, 'review'::character varying::text, 'published'::character varying::text, 'archived'::character varying::text])", name: "valid_kb_article_status"
    t.check_constraint "view_count >= 0", name: "valid_kb_view_count"
  end

  create_table "knowledge_base_attachments", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "article_id", null: false
    t.string "content_type", limit: 100
    t.datetime "created_at", null: false
    t.integer "download_count", default: 0
    t.string "file_path", limit: 1000
    t.bigint "file_size"
    t.string "filename", limit: 255, null: false
    t.jsonb "metadata", default: {}
    t.datetime "updated_at", null: false
    t.uuid "uploaded_by_id", null: false
    t.index ["article_id"]
    t.index ["download_count"]
    t.index ["filename"]
    t.index ["uploaded_by_id"]
    t.check_constraint "download_count >= 0", name: "valid_kb_download_count"
    t.check_constraint "file_size > 0", name: "valid_kb_attachment_size"
  end

  create_table "knowledge_base_categories", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.string "color"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "icon", limit: 100
    t.boolean "is_active", default: true
    t.boolean "is_public", default: true
    t.jsonb "metadata", default: {}
    t.string "name", limit: 255, null: false
    t.uuid "parent_id"
    t.string "slug", limit: 255, null: false
    t.integer "sort_order", default: 0
    t.datetime "updated_at", null: false
    t.index ["is_active"]
    t.index ["is_public"]
    t.index ["parent_id"]
    t.index ["slug"], unique: true
    t.index ["sort_order"]
  end

  create_table "knowledge_base_comments", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "article_id", null: false
    t.uuid "author_id", null: false
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.integer "helpful_count", default: 0
    t.boolean "is_helpful_vote", default: false
    t.jsonb "metadata", default: {}
    t.uuid "parent_id"
    t.string "status", limit: 50, default: "pending"
    t.datetime "updated_at", null: false
    t.index ["article_id", "status"]
    t.index ["author_id"]
    t.index ["created_at"]
    t.index ["is_helpful_vote"]
    t.index ["parent_id"]
    t.index ["status"]
    t.check_constraint "helpful_count >= 0", name: "valid_kb_comment_helpful_count"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'approved'::character varying::text, 'rejected'::character varying::text, 'spam'::character varying::text])", name: "valid_kb_comment_status"
  end

  create_table "knowledge_base_tags", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.string "color", limit: 7, default: "#6B7280"
    t.datetime "created_at", null: false
    t.text "description"
    t.boolean "is_active", default: true
    t.string "name", limit: 100, null: false
    t.string "slug", limit: 100, null: false
    t.datetime "updated_at", null: false
    t.integer "usage_count", default: 0
    t.index ["is_active"]
    t.index ["name"], unique: true
    t.index ["slug"], unique: true
    t.index ["usage_count"]
    t.check_constraint "color::text ~ '^#[0-9A-Fa-f]{6}$'::text", name: "valid_kb_tag_color"
    t.check_constraint "usage_count >= 0", name: "valid_kb_tag_usage_count"
  end

  create_table "knowledge_base_workflows", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.string "action", limit: 100, null: false
    t.uuid "article_id", null: false
    t.text "comment"
    t.datetime "created_at", null: false
    t.string "from_status", limit: 50
    t.jsonb "metadata", default: {}
    t.string "to_status", limit: 50
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["action"]
    t.index ["article_id", "created_at"]
    t.index ["created_at"]
    t.index ["from_status"]
    t.index ["to_status"]
    t.index ["user_id"]
    t.check_constraint "action::text = ANY (ARRAY['create'::character varying::text, 'edit'::character varying::text, 'publish'::character varying::text, 'unpublish'::character varying::text, 'archive'::character varying::text, 'delete'::character varying::text, 'review'::character varying::text])", name: "valid_kb_workflow_action"
  end

    add_foreign_key "knowledge_base_article_views", "users", column: "user_id"
    add_foreign_key "knowledge_base_articles", "accounts", column: "account_id"
    add_foreign_key "knowledge_base_articles", "knowledge_base_categories", column: "category_id", on_delete: :cascade
    add_foreign_key "knowledge_base_articles", "users", column: "author_id"
    add_foreign_key "knowledge_base_articles", "users", column: "last_edited_by_id"
    add_foreign_key "knowledge_base_attachments", "users", column: "uploaded_by_id"
    add_foreign_key "knowledge_base_categories", "knowledge_base_categories", column: "parent_id"
    add_foreign_key "knowledge_base_comments", "knowledge_base_comments", column: "parent_id"
    add_foreign_key "knowledge_base_comments", "users", column: "author_id"
    add_foreign_key "knowledge_base_workflows", "users", column: "user_id"
  end
end
