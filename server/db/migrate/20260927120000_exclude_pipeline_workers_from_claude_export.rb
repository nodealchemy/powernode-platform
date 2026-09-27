# frozen_string_literal: true

require Rails.root.join("db/seeds/concerns/canonical_content").to_s

# Carries the mcp_flags in db/seeds/content/canonical_agent_content.rb to
# installs that already have the rows: the five JSON pipeline workers get
# mcp_metadata["claude_code_export"] = false, so claude:sync_agents stops
# exporting them (Ai::ClaudeExport::AgentSkeletonSync::EXPORT_FLAG). A row that
# already carries the key keeps it. Down removes the flag only where it still
# holds the seeded value.
class ExcludePipelineWorkersFromClaudeExport < ActiveRecord::Migration[8.1]
  # Table-only model: no Ai::Agent callbacks (version bumps, audits) run.
  class AgentRow < ActiveRecord::Base
    self.table_name = "ai_agents"
  end

  def up
    AgentRow.reset_column_information
    CoreSeeds::CanonicalContent.apply_flags_catalog!(AgentRow)
  end

  def down
    AgentRow.reset_column_information
    CoreSeeds::CanonicalContent.revert_flags_catalog!(AgentRow)
  end
end
