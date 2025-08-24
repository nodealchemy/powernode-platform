# frozen_string_literal: true

class CreateMarketplaceInfrastructure < ActiveRecord::Migration[8.0]
  def change
    # Create apps table
    create_table :apps, id: false do |t|
      t.string :id, limit: 36, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.references :account, null: false, foreign_key: true, type: :string, limit: 36
      t.string :name, null: false, limit: 255
      t.string :slug, null: false, limit: 255
      t.text :description
      t.text :long_description
      t.string :category, limit: 100
      t.string :version, limit: 50, default: '1.0.0'
      t.string :status, limit: 50, default: 'draft'
      t.jsonb :metadata, default: {}
      t.jsonb :configuration, default: {}
      t.timestamp :published_at
      t.timestamps null: false

      t.index :status
      t.index :category
      t.index :published_at
      t.index :slug, unique: true
    end

    # Create app_plans table
    create_table :app_plans, id: false do |t|
      t.string :id, limit: 36, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.references :app, null: false, foreign_key: { on_delete: :cascade }, type: :string, limit: 36
      t.string :name, null: false, limit: 255
      t.string :slug, null: false, limit: 255
      t.text :description
      t.integer :price_cents, default: 0
      t.string :billing_interval, limit: 20, default: 'monthly'
      t.boolean :is_public, default: true
      t.boolean :is_active, default: true
      t.jsonb :features, default: []
      t.jsonb :permissions, default: []
      t.jsonb :limits, default: {}
      t.jsonb :metadata, default: {}
      t.timestamps null: false

      t.index [:app_id, :slug], unique: true
      t.index :is_public
      t.index :is_active
    end

    # Create app_features table
    create_table :app_features, id: false do |t|
      t.string :id, limit: 36, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.references :app, null: false, foreign_key: { on_delete: :cascade }, type: :string, limit: 36
      t.string :name, null: false, limit: 255
      t.string :slug, null: false, limit: 255
      t.text :description
      t.string :feature_type, limit: 50
      t.boolean :default_enabled, default: false
      t.jsonb :configuration, default: {}
      t.jsonb :dependencies, default: []
      t.timestamps null: false

      t.index [:app_id, :slug], unique: true
      t.index :feature_type
    end

    # Create marketplace_listings table
    create_table :marketplace_listings, id: false do |t|
      t.string :id, limit: 36, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.references :app, null: false, foreign_key: { on_delete: :cascade }, type: :string, limit: 36, index: { unique: true }
      t.string :title, null: false, limit: 255
      t.string :short_description, limit: 500
      t.text :long_description
      t.string :category, limit: 100
      t.jsonb :tags, default: []
      t.jsonb :screenshots, default: []
      t.string :documentation_url, limit: 500
      t.string :support_url, limit: 500
      t.string :homepage_url, limit: 500
      t.boolean :featured, default: false
      t.string :review_status, limit: 50, default: 'pending'
      t.text :review_notes
      t.timestamp :published_at
      t.timestamps null: false

      t.index :category
      t.index :review_status
      t.index :featured
      t.index :published_at
    end

    # Create app_subscriptions table
    create_table :app_subscriptions, id: false do |t|
      t.string :id, limit: 36, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.references :account, null: false, foreign_key: true, type: :string, limit: 36
      t.references :app, null: false, foreign_key: true, type: :string, limit: 36
      t.references :app_plan, null: false, foreign_key: true, type: :string, limit: 36
      t.string :status, limit: 50, default: 'active'
      t.timestamp :subscribed_at, default: -> { 'CURRENT_TIMESTAMP' }
      t.timestamp :cancelled_at
      t.timestamp :next_billing_at
      t.jsonb :configuration, default: {}
      t.jsonb :usage_metrics, default: {}
      t.timestamps null: false

      t.index [:account_id, :app_id], unique: true
      t.index :status
      t.index :next_billing_at
    end

    # Create app_reviews table
    create_table :app_reviews, id: false do |t|
      t.string :id, limit: 36, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.references :app, null: false, foreign_key: { on_delete: :cascade }, type: :string, limit: 36
      t.references :account, null: false, foreign_key: true, type: :string, limit: 36
      t.integer :rating, null: false
      t.string :title, limit: 255
      t.text :content
      t.integer :helpful_count, default: 0
      t.timestamps null: false

      t.index [:app_id, :account_id], unique: true
      t.index :rating
      t.index :created_at
    end

    # Create marketplace_categories table
    create_table :marketplace_categories, id: false do |t|
      t.string :id, limit: 36, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.string :name, null: false, limit: 255
      t.string :slug, null: false, limit: 255
      t.text :description
      t.string :icon, limit: 100
      t.integer :sort_order, default: 0
      t.boolean :is_active, default: true
      t.timestamps null: false

      t.index :slug, unique: true
      t.index :is_active
      t.index :sort_order
    end

    # Create app_analytics table
    create_table :app_analytics, id: false do |t|
      t.string :id, limit: 36, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.references :app, null: false, foreign_key: { on_delete: :cascade }, type: :string, limit: 36
      t.string :metric_name, null: false, limit: 100
      t.decimal :metric_value, precision: 15, scale: 2
      t.timestamp :recorded_at, default: -> { 'CURRENT_TIMESTAMP' }
      t.jsonb :metadata, default: {}

      t.index :metric_name
      t.index :recorded_at
    end

    # Add check constraints
    add_check_constraint :app_reviews, 'rating >= 1 AND rating <= 5', name: 'rating_range'
    add_check_constraint :apps, "status IN ('draft', 'review', 'published', 'inactive')", name: 'valid_app_status'
    add_check_constraint :app_plans, "billing_interval IN ('monthly', 'yearly', 'one_time')", name: 'valid_billing_interval'
    add_check_constraint :marketplace_listings, "review_status IN ('pending', 'approved', 'rejected')", name: 'valid_review_status'
    add_check_constraint :app_subscriptions, "status IN ('active', 'paused', 'cancelled', 'expired')", name: 'valid_subscription_status'
  end
end