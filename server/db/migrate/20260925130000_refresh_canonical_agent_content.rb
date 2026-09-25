# frozen_string_literal: true

require Rails.root.join("db/seeds/concerns/canonical_content").to_s

# Carries the canonical agent text in db/seeds/content/canonical_agent_content.rb
# ("Use when" routing sentences, the structured-output llm-judge prompt) to
# installs that already have the rows. Seeds run only on an install's first
# boot, so without this an upgraded install keeps the text it was born with.
# A field an operator edited is kept and logged
# (Ai::Agents::CanonicalContentRefresh); down restores what each write replaced.
class RefreshCanonicalAgentContent < ActiveRecord::Migration[8.1]
  # Table-only model: no Ai::Agent callbacks (version bumps, audits) run.
  class AgentRow < ActiveRecord::Base
    self.table_name = "ai_agents"
  end

  def up
    AgentRow.reset_column_information
    CoreSeeds::CanonicalContent.refresh_catalog!(AgentRow)
  end

  def down
    AgentRow.reset_column_information
    CoreSeeds::CanonicalContent.revert_catalog!(AgentRow)
  end
end
