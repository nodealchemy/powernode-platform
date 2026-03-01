# frozen_string_literal: true

class CreateCiCdPipelineTemplates < ActiveRecord::Migration[7.2]
  def change
    create_table :ci_cd_pipeline_templates, id: :uuid do |t|
      # Owner account (also acts as publisher)
      t.uuid :account_id, null: false
      t.uuid :created_by_user_id
      t.uuid :source_pipeline_id

      # Template identification
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.string :icon_url

      # Classification
      t.string :category  # review, implement, security, deploy, custom
      t.string :difficulty_level, default: "intermediate"
      t.jsonb :tags, default: []

      # Pipeline definition (extracted from source pipeline)
      t.jsonb :pipeline_definition, default: {}
      t.jsonb :default_variables, default: {}
      t.jsonb :triggers, default: {}
      t.integer :timeout_minutes, default: 30

      # Template versioning
      t.string :version, null: false, default: "1.0.0"

      # Visibility and status
      t.string :status, default: "draft"  # draft, published, archived
      t.boolean :is_public, default: false
      t.boolean :is_featured, default: false
      t.boolean :is_system, default: false
      t.datetime :published_at

      # Usage stats
      t.integer :usage_count, default: 0
      t.integer :install_count, default: 0
      t.decimal :rating, precision: 3, scale: 2, default: 0
      t.integer :rating_count, default: 0

      # Marketplace publishing
      t.boolean :is_marketplace_published, default: false
      t.string :marketplace_status  # pending, approved, rejected
      t.datetime :marketplace_submitted_at
      t.datetime :marketplace_approved_at
      t.text :marketplace_rejection_reason

      # Metadata
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :ci_cd_pipeline_templates, :account_id
    add_index :ci_cd_pipeline_templates, :created_by_user_id
    add_index :ci_cd_pipeline_templates, :source_pipeline_id
    add_index :ci_cd_pipeline_templates, :slug, unique: true
    add_index :ci_cd_pipeline_templates, :category
    add_index :ci_cd_pipeline_templates, :status
    add_index :ci_cd_pipeline_templates, :is_public
    add_index :ci_cd_pipeline_templates, :is_featured
    add_index :ci_cd_pipeline_templates, [ :is_marketplace_published, :marketplace_status ], name: "idx_cicd_pipeline_templates_marketplace"
  end
end
