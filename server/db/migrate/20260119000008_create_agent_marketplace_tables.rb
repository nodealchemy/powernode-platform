# frozen_string_literal: true

# Agent Marketplace Tables - Core marketplace infrastructure
#
# Core tables: templates, installations, reviews
# Enterprise tables (publisher accounts, categories, transactions) are in
# enterprise/server/db/migrate/20260119000008_create_marketplace_monetization_tables.rb
#
class CreateAgentMarketplaceTables < ActiveRecord::Migration[8.0]
  def change
    # ==========================================================================
    # AGENT TEMPLATES - Marketplace listings for agents
    # ==========================================================================
    create_table :ai_agent_templates, id: :uuid do |t|
      t.references :publisher, type: :uuid
      t.references :source_agent, foreign_key: { to_table: :ai_agents }, type: :uuid
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.text :long_description
      t.string :version, null: false, default: "1.0.0"
      t.string :status, null: false, default: "draft"
      t.string :visibility, null: false, default: "private"
      t.string :category
      t.string :vertical
      t.string :pricing_type, null: false, default: "free"
      t.decimal :price_usd, precision: 10, scale: 2
      t.decimal :monthly_price_usd, precision: 10, scale: 2
      t.jsonb :agent_config, default: {}
      t.jsonb :default_settings, default: {}
      t.jsonb :required_credentials, default: []
      t.jsonb :required_tools, default: []
      t.jsonb :sample_prompts, default: []
      t.jsonb :screenshots, default: []
      t.jsonb :tags, default: []
      t.jsonb :features, default: []
      t.jsonb :limitations, default: []
      t.jsonb :supported_providers, default: []
      t.text :setup_instructions
      t.text :changelog
      t.integer :installation_count, default: 0
      t.integer :active_installations, default: 0
      t.float :average_rating
      t.integer :review_count, default: 0
      t.boolean :is_featured, null: false, default: false
      t.boolean :is_verified, null: false, default: false
      t.datetime :published_at
      t.datetime :featured_at
      t.datetime :last_updated_at

      t.timestamps
    end

    add_index :ai_agent_templates, :slug, unique: true
    add_index :ai_agent_templates, [ :status, :visibility ]
    add_index :ai_agent_templates, :category
    add_index :ai_agent_templates, :vertical
    add_index :ai_agent_templates, :pricing_type
    add_index :ai_agent_templates, :is_featured
    add_index :ai_agent_templates, [ :average_rating, :installation_count ]

    # ==========================================================================
    # AGENT INSTALLATIONS - Installed templates per account
    # ==========================================================================
    create_table :ai_agent_installations, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :agent_template, null: false, foreign_key: { to_table: :ai_agent_templates }, type: :uuid
      t.references :installed_agent, foreign_key: { to_table: :ai_agents }, type: :uuid
      t.references :installed_by, foreign_key: { to_table: :users }, type: :uuid
      t.string :status, null: false, default: "active"
      t.string :installed_version
      t.string :license_type, null: false, default: "standard"
      t.jsonb :custom_config, default: {}
      t.jsonb :usage_stats, default: {}
      t.integer :executions_count, default: 0
      t.decimal :total_cost_usd, precision: 10, scale: 4, default: 0
      t.datetime :license_expires_at
      t.datetime :last_used_at
      t.datetime :last_updated_at

      t.timestamps
    end

    add_index :ai_agent_installations, [ :account_id, :agent_template_id ], unique: true, name: "idx_agent_installations_account_template"
    add_index :ai_agent_installations, :status
    add_index :ai_agent_installations, :license_expires_at

    # ==========================================================================
    # AGENT REVIEWS - Ratings and reviews
    # ==========================================================================
    create_table :ai_agent_reviews, id: :uuid do |t|
      t.references :agent_template, null: false, foreign_key: { to_table: :ai_agent_templates }, type: :uuid
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.references :installation, foreign_key: { to_table: :ai_agent_installations }, type: :uuid
      t.integer :rating, null: false
      t.string :title
      t.text :content
      t.string :status, null: false, default: "published"
      t.boolean :is_verified_purchase, null: false, default: false
      t.integer :helpful_count, default: 0
      t.integer :report_count, default: 0
      t.jsonb :pros, default: []
      t.jsonb :cons, default: []
      t.jsonb :metadata, default: {}
      t.datetime :verified_at

      t.timestamps
    end

    add_index :ai_agent_reviews, [ :agent_template_id, :account_id ], unique: true
    add_index :ai_agent_reviews, [ :agent_template_id, :status, :rating ]
    add_index :ai_agent_reviews, :status

    # ==========================================================================
    # CONSTRAINTS
    # ==========================================================================
    execute <<-SQL
      ALTER TABLE ai_agent_templates
      ADD CONSTRAINT check_template_status
      CHECK (status IN ('draft', 'pending_review', 'published', 'rejected', 'archived', 'suspended'))
    SQL

    execute <<-SQL
      ALTER TABLE ai_agent_templates
      ADD CONSTRAINT check_template_visibility
      CHECK (visibility IN ('private', 'unlisted', 'public', 'enterprise'))
    SQL

    execute <<-SQL
      ALTER TABLE ai_agent_templates
      ADD CONSTRAINT check_pricing_type
      CHECK (pricing_type IN ('free', 'one_time', 'subscription', 'usage_based', 'freemium'))
    SQL

    execute <<-SQL
      ALTER TABLE ai_agent_installations
      ADD CONSTRAINT check_installation_status
      CHECK (status IN ('active', 'paused', 'expired', 'cancelled', 'pending_update'))
    SQL

    execute <<-SQL
      ALTER TABLE ai_agent_reviews
      ADD CONSTRAINT check_review_rating
      CHECK (rating >= 1 AND rating <= 5)
    SQL

    execute <<-SQL
      ALTER TABLE ai_agent_reviews
      ADD CONSTRAINT check_review_status
      CHECK (status IN ('pending', 'published', 'hidden', 'flagged', 'removed'))
    SQL
  end
end
