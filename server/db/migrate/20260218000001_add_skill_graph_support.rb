# frozen_string_literal: true

class AddSkillGraphSupport < ActiveRecord::Migration[8.0]
  def change
    # Link KG nodes to skills
    add_reference :ai_knowledge_graph_nodes, :ai_skill,
                  type: :uuid,
                  foreign_key: { to_table: :ai_skills },
                  null: true,
                  index: false

    # Partial unique index: one active skill node per account per skill
    add_index :ai_knowledge_graph_nodes, [:account_id, :ai_skill_id],
              unique: true,
              where: "ai_skill_id IS NOT NULL AND status = 'active'",
              name: "idx_kg_nodes_unique_active_skill"

    # Team skill graph configuration
    add_column :ai_agent_teams, :skill_graph_config, :jsonb, default: {}
  end
end
