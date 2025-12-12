# frozen_string_literal: true

class CreateKnowledgeBaseSystem < ActiveRecord::Migration[8.0]
  def change
    # Create knowledge_base_categories table
    create_table :knowledge_base_categories, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.string :name, null: false, limit: 255
      t.string :slug, null: false, limit: 255
      t.text :description
      t.references :parent, null: true, foreign_key: { to_table: :knowledge_base_categories }, type: :uuid
      t.string :icon, limit: 100
      t.integer :sort_order, default: 0
      t.boolean :is_active, default: true
      t.boolean :is_public, default: true
      t.jsonb :metadata, default: {}
      t.timestamps null: false

      t.index [ :slug ], unique: true, name: 'idx_knowledge_base_categories_on_slug_unique'
      t.index [ :is_active ], name: 'idx_knowledge_base_categories_on_is_active'
      t.index [ :is_public ], name: 'idx_knowledge_base_categories_on_is_public'
      t.index [ :sort_order ], name: 'idx_knowledge_base_categories_on_sort_order'
    end

    # Create knowledge_base_tags table
    create_table :knowledge_base_tags, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.string :name, null: false, limit: 100
      t.string :slug, null: false, limit: 100
      t.string :color, limit: 7, default: '#6B7280'
      t.text :description
      t.boolean :is_active, default: true
      t.integer :usage_count, default: 0
      t.timestamps null: false

      t.index [ :slug ], unique: true, name: 'idx_knowledge_base_tags_on_slug_unique'
      t.index [ :name ], unique: true, name: 'idx_knowledge_base_tags_on_name_unique'
      t.index [ :is_active ], name: 'idx_knowledge_base_tags_on_is_active'
      t.index [ :usage_count ], name: 'idx_knowledge_base_tags_on_usage_count'
    end

    # Create knowledge_base_articles table
    create_table :knowledge_base_articles, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.uuid :category_id, null: false
      t.references :author, null: false, foreign_key: { to_table: :users }, type: :uuid
      t.references :last_edited_by, null: true, foreign_key: { to_table: :users }, type: :uuid
      t.string :title, null: false, limit: 255
      t.string :slug, null: false, limit: 255
      t.text :content, null: false
      t.text :excerpt
      t.string :status, default: 'draft', limit: 50
      t.boolean :is_featured, default: false
      t.boolean :is_public, default: true
      t.integer :sort_order, default: 0
      t.integer :view_count, default: 0
      t.integer :views_count, default: 0
      t.integer :likes_count, default: 0
      t.integer :helpful_count, default: 0
      t.integer :not_helpful_count, default: 0
      t.decimal :helpfulness_score, precision: 5, scale: 2, default: 0.0
      t.integer :reading_time_minutes
      t.string :meta_title, limit: 255
      t.text :meta_description
      t.datetime :published_at
      t.datetime :last_reviewed_at
      t.jsonb :metadata, default: {}
      t.tsvector :search_vector
      t.timestamps null: false

      t.index [ :slug ], unique: true, name: 'idx_knowledge_base_articles_on_slug_unique'
      t.index [ :category_id ], name: 'idx_knowledge_base_articles_on_category_id'
      t.index [ :author_id ], name: 'idx_knowledge_base_articles_on_author_id'
      t.index [ :status ], name: 'idx_knowledge_base_articles_on_status'
      t.index [ :is_featured ], name: 'idx_knowledge_base_articles_on_is_featured'
      t.index [ :is_public ], name: 'idx_knowledge_base_articles_on_is_public'
      t.index [ :published_at ], name: 'idx_knowledge_base_articles_on_published_at'
      t.index [ :view_count ], name: 'idx_knowledge_base_articles_on_view_count'
      t.index [ :helpfulness_score ], name: 'idx_knowledge_base_articles_on_helpfulness_score'
      t.index [ :search_vector ], using: :gin, name: 'idx_knowledge_base_articles_on_search_vector'
    end

    # Create knowledge_base_article_tags junction table
    create_table :knowledge_base_article_tags, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.uuid :article_id, null: false
      t.uuid :tag_id, null: false
      t.timestamps null: false

      t.index [ :article_id, :tag_id ], unique: true, name: 'index_kb_article_tags_unique'
      t.index [ :tag_id ], name: 'idx_kb_article_tags_on_tag_id'
    end

    # Create knowledge_base_attachments table
    create_table :knowledge_base_attachments, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.uuid :article_id, null: false
      t.string :filename, null: false, limit: 255
      t.string :file_path, limit: 1000
      t.string :content_type, limit: 100
      t.bigint :file_size
      t.references :uploaded_by, null: false, foreign_key: { to_table: :users }, type: :uuid
      t.integer :download_count, default: 0
      t.jsonb :metadata, default: {}
      t.timestamps null: false

      t.index [ :article_id ], name: 'idx_kb_attachments_on_article_id'
      t.index [ :uploaded_by_id ], name: 'idx_kb_attachments_on_uploaded_by_id'
      t.index [ :filename ], name: 'idx_kb_attachments_on_filename'
      t.index [ :download_count ], name: 'idx_kb_attachments_on_download_count'
    end

    # Create knowledge_base_comments table
    create_table :knowledge_base_comments, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.uuid :article_id, null: false
      t.references :author, null: false, foreign_key: { to_table: :users }, type: :uuid
      t.references :parent, null: true, foreign_key: { to_table: :knowledge_base_comments }, type: :uuid
      t.text :content, null: false
      t.string :status, default: 'published', limit: 50
      t.boolean :is_helpful_vote, default: false
      t.integer :helpful_count, default: 0
      t.jsonb :metadata, default: {}
      t.timestamps null: false

      t.index [ :article_id, :status ], name: 'idx_kb_comments_on_article_status'
      t.index [ :author_id ], name: 'idx_kb_comments_on_author_id'
      t.index [ :parent_id ], name: 'idx_kb_comments_on_parent_id'
      t.index [ :status ], name: 'idx_kb_comments_on_status'
      t.index [ :is_helpful_vote ], name: 'idx_kb_comments_on_is_helpful_vote'
      t.index [ :created_at ], name: 'idx_kb_comments_on_created_at'
    end

    # Create knowledge_base_article_views table - Analytics
    create_table :knowledge_base_article_views, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.uuid :article_id, null: false
      t.references :user, null: true, foreign_key: true, type: :uuid
      t.string :session_id, limit: 255
      t.string :ip_address, limit: 45
      t.string :user_agent, limit: 1000
      t.string :referrer, limit: 1000
      t.integer :reading_time_seconds
      t.boolean :read_to_end, default: false
      t.jsonb :metadata, default: {}
      t.datetime :viewed_at, null: false
      t.timestamps null: false

      t.index [ :article_id, :viewed_at ], name: 'idx_kb_article_views_on_article_viewed_at'
      t.index [ :user_id ], name: 'idx_kb_article_views_on_user_id'
      t.index [ :session_id ], name: 'idx_kb_article_views_on_session_id'
      t.index [ :viewed_at ], name: 'idx_kb_article_views_on_viewed_at'
      t.index [ :read_to_end ], name: 'idx_kb_article_views_on_read_to_end'
    end

    # Create knowledge_base_workflows table - Editorial workflow
    create_table :knowledge_base_workflows, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.uuid :article_id, null: false
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.string :action, null: false, limit: 100
      t.string :from_status, limit: 50
      t.string :to_status, limit: 50
      t.text :comment
      t.jsonb :metadata, default: {}
      t.timestamps null: false

      t.index [ :article_id, :created_at ], name: 'idx_kb_workflows_on_article_created_at'
      t.index [ :user_id ], name: 'idx_kb_workflows_on_user_id'
      t.index [ :action ], name: 'idx_kb_workflows_on_action'
      t.index [ :from_status ], name: 'idx_kb_workflows_on_from_status'
      t.index [ :to_status ], name: 'idx_kb_workflows_on_to_status'
      t.index [ :created_at ], name: 'idx_kb_workflows_on_created_at'
    end

    # Add full-text search functionality
    execute <<-SQL
      CREATE OR REPLACE FUNCTION update_knowledge_base_search_vector()
      RETURNS TRIGGER AS $$
      BEGIN
        NEW.search_vector := to_tsvector('english',#{' '}
          COALESCE(NEW.title, '') || ' ' ||#{' '}
          COALESCE(NEW.content, '') || ' ' ||
          COALESCE(NEW.excerpt, '')
        );
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;

      CREATE TRIGGER update_knowledge_base_articles_search_vector
      BEFORE INSERT OR UPDATE ON knowledge_base_articles
      FOR EACH ROW EXECUTE FUNCTION update_knowledge_base_search_vector();
    SQL

    # Add check constraints for knowledge base
    add_check_constraint :knowledge_base_articles, "status IN ('draft', 'review', 'published', 'archived')", name: 'valid_kb_article_status'
    add_check_constraint :knowledge_base_articles, 'view_count >= 0', name: 'valid_kb_view_count'
    add_check_constraint :knowledge_base_articles, 'helpful_count >= 0 AND not_helpful_count >= 0', name: 'valid_kb_helpful_counts'
    add_check_constraint :knowledge_base_articles, 'helpfulness_score >= 0 AND helpfulness_score <= 100', name: 'valid_kb_helpfulness_score'
    add_check_constraint :knowledge_base_articles, 'reading_time_minutes IS NULL OR reading_time_minutes > 0', name: 'valid_kb_reading_time'

    add_check_constraint :knowledge_base_tags, 'usage_count >= 0', name: 'valid_kb_tag_usage_count'
    add_check_constraint :knowledge_base_tags, "color ~ '^#[0-9A-Fa-f]{6}$'", name: 'valid_kb_tag_color'

    add_check_constraint :knowledge_base_attachments, 'file_size > 0', name: 'valid_kb_attachment_size'
    add_check_constraint :knowledge_base_attachments, 'download_count >= 0', name: 'valid_kb_download_count'

    add_check_constraint :knowledge_base_comments, "status IN ('pending', 'published', 'hidden', 'spam')", name: 'valid_kb_comment_status'
    add_check_constraint :knowledge_base_comments, 'helpful_count >= 0', name: 'valid_kb_comment_helpful_count'

    add_check_constraint :knowledge_base_article_views, 'reading_time_seconds IS NULL OR reading_time_seconds >= 0', name: 'valid_kb_reading_time_seconds'

    add_check_constraint :knowledge_base_workflows, "action IN ('create', 'edit', 'publish', 'unpublish', 'archive', 'delete', 'review')", name: 'valid_kb_workflow_action'
  end

  def down
    # Drop triggers and functions
    execute <<-SQL
      DROP TRIGGER IF EXISTS update_knowledge_base_articles_search_vector ON knowledge_base_articles;
      DROP FUNCTION IF EXISTS update_knowledge_base_search_vector();
    SQL

    # Tables will be dropped automatically by Rails migration rollback
  end
end
