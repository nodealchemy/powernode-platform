# frozen_string_literal: true

# Add missing foreign key constraint between knowledge_base_articles and knowledge_base_categories
# This ensures data integrity at the database level
class AddForeignKeyToKnowledgeBaseArticles < ActiveRecord::Migration[7.2]
  def up
    # Add foreign key constraint if it doesn't already exist
    unless foreign_key_exists?(:knowledge_base_articles, :knowledge_base_categories)
      add_foreign_key :knowledge_base_articles, :knowledge_base_categories,
                      column: :category_id,
                      on_delete: :cascade,
                      validate: false

      # Validate existing data (this allows zero-downtime deployment)
      validate_foreign_key :knowledge_base_articles, :knowledge_base_categories
    end
  end

  def down
    if foreign_key_exists?(:knowledge_base_articles, :knowledge_base_categories)
      remove_foreign_key :knowledge_base_articles, :knowledge_base_categories
    end
  end
end
