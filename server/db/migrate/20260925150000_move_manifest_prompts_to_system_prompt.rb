# frozen_string_literal: true

require Rails.root.join("db/seeds/concerns/canonical_content").to_s

# Three canonical seeds (strategic-planner, research-analyst,
# system-quality-assurance) stored their persona prompt in
# mcp_tool_manifest["configuration"]["system_prompt"]. No prompt path reads it:
# Ai::Agent#system_prompt and #build_system_prompt_with_profile read
# mcp_metadata["system_prompt"], and Ai::McpAgentExecutor only merges the
# manifest configuration into an execution context whose :system_prompt key
# nothing consumes. Those agents ran with no persona.
#
# up:
#   - re-applies db/seeds/content/canonical_agent_content.rb, which now carries
#     their reworded prompts: a canonical row's blank system_prompt is filled,
#     an operator-set one is kept (Ai::Agents::CanonicalContentRefresh);
#   - any OTHER row carrying the dead key (an account clone) whose
#     mcp_metadata has no system_prompt gets the text it already had, moved to
#     where it is read;
#   - the dead key is removed from every row.
# down reverts only this wave's prompt writes (wave 1's descriptions are
# 20260925130000's to revert); the dead key is not restored, since
# nothing read it.
class MoveManifestPromptsToSystemPrompt < ActiveRecord::Migration[8.1]
  MOVED = %w[strategic-planner research-analyst system-quality-assurance].freeze

  class AgentRow < ActiveRecord::Base
    self.table_name = "ai_agents"
  end

  def up
    AgentRow.reset_column_information
    CoreSeeds::CanonicalContent.refresh_catalog!(AgentRow)

    AgentRow.where("(mcp_tool_manifest -> 'configuration') ? :key", key: "system_prompt").find_each do |agent|
      configuration = agent.mcp_tool_manifest["configuration"]
      dead_prompt = configuration["system_prompt"]
      metadata = agent.mcp_metadata || {}
      if metadata["system_prompt"].blank? && dead_prompt.present?
        agent.mcp_metadata = metadata.merge("system_prompt" => dead_prompt)
      end
      agent.mcp_tool_manifest = agent.mcp_tool_manifest.merge("configuration" => configuration.except("system_prompt"))
      agent.save!
    end
  end

  def down
    AgentRow.reset_column_information
    CoreSeeds::CanonicalContent.revert_catalog!(AgentRow, only: MOVED.index_with { [ :system_prompt ] })
  end
end
