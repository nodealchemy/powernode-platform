# frozen_string_literal: true

class CreateAiSkillProposals < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_skill_proposals, id: :uuid do |t|
      t.references :account, type: :uuid, foreign_key: true, null: false
      t.references :proposed_by_agent, type: :uuid, foreign_key: { to_table: :ai_agents }, null: true
      t.references :proposed_by_user, type: :uuid, foreign_key: { to_table: :users }, null: true
      t.references :reviewed_by, type: :uuid, foreign_key: { to_table: :users }, null: true, index: false
      t.references :created_skill, type: :uuid, foreign_key: { to_table: :ai_skills }, null: true, index: false
      t.references :parent_proposal, type: :uuid, foreign_key: { to_table: :ai_skill_proposals }, null: true

      t.string :name, null: false
      t.string :slug
      t.text :description
      t.string :category
      t.text :system_prompt
      t.jsonb :commands, default: []
      t.jsonb :tags, default: []
      t.jsonb :metadata, default: {}

      t.string :status, default: 'draft', null: false
      t.string :trust_tier_at_proposal
      t.boolean :auto_approved, default: false
      t.text :rejection_reason

      t.jsonb :research_report, default: {}
      t.jsonb :suggested_dependencies, default: []
      t.jsonb :overlap_analysis, default: {}
      t.float :confidence_score, default: 0.0

      t.datetime :proposed_at
      t.datetime :reviewed_at
      t.timestamps
    end

    add_index :ai_skill_proposals, [:account_id, :name],
              unique: true,
              where: "status NOT IN ('rejected', 'created')",
              name: "idx_skill_proposals_unique_active_name"
  end
end
