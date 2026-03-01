# frozen_string_literal: true

class ChangeSlugUniqueConstraintOnAiProviders < ActiveRecord::Migration[8.1]
  def change
    remove_index :ai_providers, :slug, unique: true
    add_index :ai_providers, [:slug, :account_id], unique: true
  end
end
