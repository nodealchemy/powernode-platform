# frozen_string_literal: true

class SimplifySkillMcpServerJoin < ActiveRecord::Migration[8.0]
  def up
    # Create simple HABTM join table (no primary key, no timestamps, no role)
    create_table :ai_skills_mcp_servers, id: false do |t|
      t.references :ai_skill, type: :uuid, null: false, foreign_key: { to_table: :ai_skills }, index: false
      t.references :mcp_server, type: :uuid, null: false, foreign_key: true, index: false
    end

    add_index :ai_skills_mcp_servers, [:ai_skill_id, :mcp_server_id], unique: true,
              name: "idx_skills_mcp_servers_unique"
    add_index :ai_skills_mcp_servers, :mcp_server_id,
              name: "idx_skills_mcp_servers_on_mcp_server"

    # Migrate existing connector data
    execute <<-SQL
      INSERT INTO ai_skills_mcp_servers (ai_skill_id, mcp_server_id)
      SELECT DISTINCT ai_skill_id, mcp_server_id
      FROM ai_skill_connectors
      ON CONFLICT DO NOTHING
    SQL

    # Drop old connectors table
    drop_table :ai_skill_connectors
  end

  def down
    create_table :ai_skill_connectors, id: :uuid do |t|
      t.references :ai_skill, type: :uuid, null: false, foreign_key: { to_table: :ai_skills }, index: true
      t.references :mcp_server, type: :uuid, null: false, foreign_key: true, index: true
      t.string :role, default: "primary"
      t.timestamps
    end

    add_index :ai_skill_connectors, [:ai_skill_id, :mcp_server_id], unique: true

    execute <<-SQL
      INSERT INTO ai_skill_connectors (id, ai_skill_id, mcp_server_id, role, created_at, updated_at)
      SELECT gen_random_uuid(), ai_skill_id, mcp_server_id, 'primary', NOW(), NOW()
      FROM ai_skills_mcp_servers
    SQL

    drop_table :ai_skills_mcp_servers
  end
end
