# frozen_string_literal: true

class CreateAiMissionTemplates < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_mission_templates, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :account, type: :uuid, index: true # nullable for system templates
      t.string :name, null: false
      t.text :description
      t.string :template_type, null: false, default: "account" # system/account/community
      t.string :mission_type, null: false # development/research/operations/custom
      t.jsonb :phases, default: -> { "'[]'" } # Array of phase definitions
      t.jsonb :approval_gates, default: -> { "'[]'" } # Which phases are approval gates
      t.jsonb :rejection_mappings, default: -> { "'{}'" } # gate -> rollback_phase mapping
      t.jsonb :skill_compositions, default: -> { "'{}'" } # Pre-mapped skills per phase
      t.jsonb :default_configuration, default: -> { "'{}'" }
      t.integer :version, default: 1
      t.string :status, default: "active"
      t.boolean :is_default, default: false

      t.timestamps
    end

    add_index :ai_mission_templates, [:account_id, :template_type]
    add_index :ai_mission_templates, [:mission_type, :status]
    add_index :ai_mission_templates, :is_default, where: "is_default = true"
  end
end
