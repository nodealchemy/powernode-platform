# frozen_string_literal: true

class AddColorToKnowledgeBaseCategories < ActiveRecord::Migration[8.1]
  def change
    add_column :knowledge_base_categories, :color, :string
  end
end
