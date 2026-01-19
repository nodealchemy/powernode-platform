# frozen_string_literal: true

class CreateMarketplaceReviews < ActiveRecord::Migration[8.0]
  def change
    create_table :marketplace_reviews, id: :uuid do |t|
      # Polymorphic association to any marketplace item type
      t.string :reviewable_type, null: false
      t.uuid :reviewable_id, null: false

      # Review author
      t.references :account, type: :uuid, null: false, foreign_key: true
      t.references :user, type: :uuid, null: false, foreign_key: true

      # Review content
      t.integer :rating, null: false
      t.string :title, limit: 255
      t.text :content

      # Metadata
      t.boolean :verified_purchase, default: false, null: false
      t.integer :helpful_count, default: 0, null: false
      t.string :moderation_status, default: "approved", null: false

      t.timestamps
    end

    # Indexes for efficient queries
    add_index :marketplace_reviews, [ :reviewable_type, :reviewable_id ], name: "idx_marketplace_reviews_on_reviewable"
    add_index :marketplace_reviews, :moderation_status
    add_index :marketplace_reviews, :rating
    add_index :marketplace_reviews, [ :account_id, :reviewable_type, :reviewable_id ],
              unique: true,
              name: "idx_marketplace_reviews_unique_per_account"
  end
end
