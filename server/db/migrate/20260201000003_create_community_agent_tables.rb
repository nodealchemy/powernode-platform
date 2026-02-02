# frozen_string_literal: true

class CreateCommunityAgentTables < ActiveRecord::Migration[8.0]
  def change
    # Community Agents - Public agent registry
    create_table :community_agents, id: :uuid do |t|
      t.references :owner_account, null: false, foreign_key: { to_table: :accounts }, type: :uuid, index: true
      t.references :agent, null: false, foreign_key: { to_table: :ai_agents }, type: :uuid, index: true
      t.references :agent_card, foreign_key: { to_table: :ai_agent_cards }, type: :uuid, index: true
      t.references :published_by, foreign_key: { to_table: :users }, type: :uuid

      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.text :long_description  # Markdown formatted
      t.string :category  # automation, analysis, integration, custom
      t.jsonb :tags, default: []
      t.string :visibility, default: "public"  # public, unlisted, private
      t.string :status, default: "pending"  # pending, active, suspended, deprecated

      # A2A endpoint info
      t.string :endpoint_url
      t.jsonb :capabilities, default: {}  # skills, streaming, push notifications
      t.jsonb :authentication, default: {}  # Auth requirements
      t.string :protocol_version, default: "0.3"

      # Federation
      t.string :federation_key  # For cross-organization discovery
      t.boolean :federated, default: false

      # Metrics
      t.decimal :reputation_score, precision: 5, scale: 2, default: 0.0
      t.integer :task_count, default: 0
      t.integer :success_count, default: 0
      t.integer :failure_count, default: 0
      t.decimal :avg_rating, precision: 3, scale: 2, default: 0.0
      t.integer :rating_count, default: 0
      t.integer :subscriber_count, default: 0
      t.decimal :avg_response_time_ms, precision: 10, scale: 2

      # Verification
      t.boolean :verified, default: false
      t.datetime :verified_at
      t.references :verified_by, foreign_key: { to_table: :users }, type: :uuid

      # Publishing info
      t.datetime :published_at
      t.datetime :last_updated_at
      t.string :version, default: "1.0.0"
      t.text :changelog

      t.timestamps
    end

    add_index :community_agents, :slug, unique: true
    add_index :community_agents, :visibility
    add_index :community_agents, :status
    add_index :community_agents, :category
    add_index :community_agents, :verified
    add_index :community_agents, :reputation_score
    add_index :community_agents, :task_count
    add_index :community_agents, :federation_key, unique: true, where: "federation_key IS NOT NULL"
    add_index :community_agents, :tags, using: :gin

    add_check_constraint :community_agents, "visibility IN ('public', 'unlisted', 'private')", name: "community_agents_visibility_check"
    add_check_constraint :community_agents, "status IN ('pending', 'active', 'suspended', 'deprecated')", name: "community_agents_status_check"

    # Community Agent Ratings - User ratings
    create_table :community_agent_ratings, id: :uuid do |t|
      t.references :community_agent, null: false, foreign_key: true, type: :uuid, index: true
      t.references :account, null: false, foreign_key: true, type: :uuid, index: true
      t.references :user, null: false, foreign_key: true, type: :uuid, index: true
      t.references :a2a_task, foreign_key: { to_table: :ai_a2a_tasks }, type: :uuid  # Associated task

      t.integer :rating, null: false  # 1-5 stars
      t.text :review
      t.jsonb :rating_dimensions, default: {}  # accuracy, speed, reliability, etc.
      t.boolean :verified_usage, default: false  # Rating from actual task usage

      t.datetime :edited_at
      t.boolean :hidden, default: false  # Moderation
      t.text :moderation_reason

      t.timestamps
    end

    add_index :community_agent_ratings, [:community_agent_id, :account_id], unique: true, name: "idx_community_ratings_unique_per_account"
    add_index :community_agent_ratings, :rating
    add_index :community_agent_ratings, :verified_usage

    add_check_constraint :community_agent_ratings, "rating >= 1 AND rating <= 5", name: "community_ratings_range_check"

    # Community Agent Reports - Abuse reports
    create_table :community_agent_reports, id: :uuid do |t|
      t.references :community_agent, null: false, foreign_key: true, type: :uuid, index: true
      t.references :reported_by_account, null: false, foreign_key: { to_table: :accounts }, type: :uuid, index: true
      t.references :reported_by_user, null: false, foreign_key: { to_table: :users }, type: :uuid

      t.string :report_type, null: false  # malicious, spam, inappropriate, copyright, other
      t.text :description, null: false
      t.jsonb :evidence, default: {}  # Task IDs, logs, etc.
      t.string :status, default: "pending"  # pending, investigating, resolved, dismissed

      t.text :resolution_notes
      t.references :resolved_by, foreign_key: { to_table: :users }, type: :uuid
      t.datetime :resolved_at

      t.timestamps
    end

    add_index :community_agent_reports, :report_type
    add_index :community_agent_reports, :status
    add_index :community_agent_reports, [:community_agent_id, :status]

    add_check_constraint :community_agent_reports, "report_type IN ('malicious', 'spam', 'inappropriate', 'copyright', 'other')", name: "community_reports_type_check"
    add_check_constraint :community_agent_reports, "status IN ('pending', 'investigating', 'resolved', 'dismissed')", name: "community_reports_status_check"

    # Federation Partners - Trusted organizations
    create_table :federation_partners, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid, index: true
      t.references :created_by, foreign_key: { to_table: :users }, type: :uuid

      t.string :name, null: false
      t.string :organization_id, null: false  # External org identifier
      t.string :endpoint_url, null: false
      t.string :status, default: "pending"  # pending, active, suspended, revoked

      # Security
      t.text :public_key  # For mTLS/signature verification
      t.string :federation_token_hash  # Hashed token for API auth
      t.jsonb :allowed_capabilities, default: []  # What they can access
      t.jsonb :tls_config, default: {}  # Certificate pinning config

      # Trust settings
      t.integer :trust_level, default: 1  # 1-5
      t.boolean :auto_approve_agents, default: false
      t.integer :max_requests_per_hour, default: 1000

      # Activity tracking
      t.integer :request_count, default: 0
      t.integer :agent_count, default: 0
      t.datetime :last_sync_at
      t.datetime :last_request_at

      t.datetime :approved_at
      t.references :approved_by, foreign_key: { to_table: :users }, type: :uuid

      t.timestamps
    end

    add_index :federation_partners, :organization_id, unique: true
    add_index :federation_partners, :status
    add_index :federation_partners, [:account_id, :status]
    add_index :federation_partners, :trust_level

    add_check_constraint :federation_partners, "status IN ('pending', 'active', 'suspended', 'revoked')", name: "federation_partners_status_check"
    add_check_constraint :federation_partners, "trust_level >= 1 AND trust_level <= 5", name: "federation_partners_trust_check"
  end
end
