# frozen_string_literal: true

class CreateAiAgentTemplates < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_agent_templates, id: :uuid do |t|
      t.uuid :creator_id, null: false
      t.string :name, null: false, limit: 255
      t.string :slug, null: false, limit: 150
      t.text :description
      t.string :category, limit: 100
      t.jsonb :template_config, null: false, default: {}
      t.jsonb :default_parameters, default: {}
      t.jsonb :required_capabilities, default: []
      t.jsonb :supported_providers, default: []
      t.string :version, default: '1.0.0'
      t.boolean :is_public, default: false
      t.boolean :is_featured, default: false
      t.integer :usage_count, default: 0
      t.decimal :average_rating, precision: 3, scale: 2, default: 0
      t.integer :rating_count, default: 0
      t.jsonb :tags, default: []
      t.text :instructions
      t.jsonb :example_inputs, default: []
      t.jsonb :example_outputs, default: []
      t.timestamps

      t.index :creator_id
      t.index :slug, unique: true
      t.index :category
      t.index :is_public
      t.index :is_featured
      t.index :usage_count
      t.index :average_rating
      t.index [ :is_public, :category ]
      t.index [ :is_public, :is_featured ]

      t.foreign_key :users, column: :creator_id, on_delete: :restrict
    end

    add_index :ai_agent_templates, :tags, using: 'gin'
    add_index :ai_agent_templates, :supported_providers, using: 'gin'
  end
end
