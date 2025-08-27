# frozen_string_literal: true

class CreateKnowledgeBaseSystem < ActiveRecord::Migration[8.0]
  def change
    # Enable UUID extension if not already enabled
    enable_extension 'pgcrypto' unless extension_enabled?('pgcrypto')
    
    # Categories table  
    create_table :knowledge_base_categories, id: :uuid do |t|
      t.string :name, null: false, limit: 255
      t.string :slug, null: false, limit: 255
      t.text :description
      t.uuid :parent_id
      t.integer :sort_order, default: 0, null: false
      t.boolean :is_public, default: true, null: false
      t.jsonb :metadata, default: {}
      t.timestamps null: false

      t.index :slug, unique: true
      t.index :parent_id
      t.index [:is_public, :sort_order]
      t.foreign_key :knowledge_base_categories, column: :parent_id
    end

    # Tags table
    create_table :knowledge_base_tags, id: :uuid do |t|
      t.string :name, null: false, limit: 100
      t.string :slug, null: false, limit: 100
      t.text :description, limit: 500
      t.string :color, default: '#3B82F6', limit: 7
      t.integer :usage_count, default: 0, null: false
      t.timestamps null: false

      t.index :name, unique: true
      t.index :slug, unique: true
      t.index :usage_count
    end

    # Articles table
    create_table :knowledge_base_articles, id: :uuid do |t|
      t.string :title, null: false, limit: 255
      t.string :slug, null: false, limit: 255
      t.text :content, null: false
      t.text :excerpt, limit: 500
      t.uuid :category_id, null: false
      t.uuid :author_id, null: false
      t.string :status, default: 'draft', null: false, limit: 20
      t.boolean :is_public, default: false, null: false
      t.boolean :is_featured, default: false, null: false
      t.datetime :published_at
      t.integer :sort_order, default: 0, null: false
      t.integer :views_count, default: 0, null: false
      t.integer :likes_count, default: 0, null: false
      t.jsonb :metadata, default: {}
      t.tsvector :search_vector
      t.timestamps null: false

      t.index :slug, unique: true
      t.index :category_id
      t.index :author_id
      t.index :status
      t.index [:is_public, :status]
      t.index [:is_featured, :published_at]
      t.index :published_at
      t.index :views_count
      t.index :search_vector, using: :gin
      t.foreign_key :knowledge_base_categories, column: :category_id
      t.foreign_key :users, column: :author_id
    end

    # Article-Tag junction table
    create_table :knowledge_base_article_tags, id: :uuid do |t|
      t.uuid :article_id, null: false
      t.uuid :tag_id, null: false
      t.timestamps null: false

      t.index [:article_id, :tag_id], unique: true
      t.index :tag_id
      t.foreign_key :knowledge_base_articles, column: :article_id
      t.foreign_key :knowledge_base_tags, column: :tag_id
    end

    # Attachments table
    create_table :knowledge_base_attachments, id: :uuid do |t|
      t.uuid :article_id, null: false
      t.string :filename, null: false, limit: 255
      t.string :content_type, limit: 100
      t.bigint :file_size
      t.text :file_path
      t.integer :download_count, default: 0, null: false
      t.uuid :uploaded_by_id, null: false
      t.jsonb :metadata, default: {}
      t.timestamps null: false

      t.index :article_id
      t.index :uploaded_by_id
      t.index :filename
      t.foreign_key :knowledge_base_articles, column: :article_id
      t.foreign_key :users, column: :uploaded_by_id
    end

    # Comments table
    create_table :knowledge_base_comments, id: :uuid do |t|
      t.uuid :article_id, null: false
      t.uuid :author_id, null: false
      t.uuid :parent_id
      t.text :content, null: false
      t.string :status, default: 'published', null: false, limit: 20
      t.jsonb :metadata, default: {}
      t.timestamps null: false

      t.index :article_id
      t.index :author_id
      t.index :parent_id
      t.index :status
      t.index :created_at
      t.foreign_key :knowledge_base_articles, column: :article_id
      t.foreign_key :users, column: :author_id
      t.foreign_key :knowledge_base_comments, column: :parent_id
    end

    # Article views tracking table
    create_table :knowledge_base_article_views, id: :uuid do |t|
      t.uuid :article_id, null: false
      t.uuid :user_id
      t.string :session_id, limit: 255
      t.string :ip_address, limit: 45
      t.text :user_agent
      t.jsonb :metadata, default: {}
      t.timestamps null: false

      t.index :article_id
      t.index :user_id
      t.index :session_id
      t.index :created_at
      t.foreign_key :knowledge_base_articles, column: :article_id
      t.foreign_key :users, column: :user_id
    end

    # Workflows table (for approval processes)
    create_table :knowledge_base_workflows, id: :uuid do |t|
      t.uuid :article_id, null: false
      t.string :workflow_type, null: false, limit: 50
      t.string :status, default: 'pending', null: false, limit: 20
      t.uuid :initiated_by_id, null: false
      t.uuid :assigned_to_id
      t.text :notes
      t.datetime :due_date
      t.datetime :completed_at
      t.jsonb :workflow_data, default: {}
      t.jsonb :metadata, default: {}
      t.timestamps null: false

      t.index :article_id
      t.index :initiated_by_id
      t.index :assigned_to_id
      t.index :status
      t.index :workflow_type
      t.index :due_date
      t.foreign_key :knowledge_base_articles, column: :article_id
      t.foreign_key :users, column: :initiated_by_id
      t.foreign_key :users, column: :assigned_to_id
    end

    # Full-text search triggers
    reversible do |dir|
      dir.up do
        execute <<-SQL
          CREATE OR REPLACE FUNCTION update_knowledge_base_search_vector() 
          RETURNS trigger AS $$
          BEGIN
            NEW.search_vector := to_tsvector('english', 
              COALESCE(NEW.title, '') || ' ' || 
              COALESCE(NEW.content, '') || ' ' || 
              COALESCE(NEW.excerpt, '')
            );
            RETURN NEW;
          END;
          $$ LANGUAGE plpgsql;

          CREATE TRIGGER update_knowledge_base_articles_search_vector 
            BEFORE INSERT OR UPDATE ON knowledge_base_articles 
            FOR EACH ROW 
            EXECUTE FUNCTION update_knowledge_base_search_vector();
        SQL
      end

      dir.down do
        execute <<-SQL
          DROP TRIGGER IF EXISTS update_knowledge_base_articles_search_vector ON knowledge_base_articles;
          DROP FUNCTION IF EXISTS update_knowledge_base_search_vector();
        SQL
      end
    end
  end
end