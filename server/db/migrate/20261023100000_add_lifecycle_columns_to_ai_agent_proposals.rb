# frozen_string_literal: true

# The agent-proposal lifecycle (approve -> hand off -> implemented) needs somewhere to
# record what an approval produced and what closed it. Additive only: every column is
# nullable, so existing rows and an old build reading the table are unaffected.
#
#   implemented_at   when the work the proposal asked for was recorded as done
#   implemented_ref  what proves it: a landed commit sha, an agent id, a gitops ref
#   handoff_kind     what approval handed the work to: dev_task | campaign_proposal | agent |
#                    gitops | acknowledged (acknowledgement-only: nothing was started)
#   handoff_id       the record the handoff created (task, campaign proposal, agent); nil for
#                    gitops and acknowledged
class AddLifecycleColumnsToAiAgentProposals < ActiveRecord::Migration[8.1]
  def change
    add_column :ai_agent_proposals, :implemented_at, :datetime
    add_column :ai_agent_proposals, :implemented_ref, :string
    add_column :ai_agent_proposals, :handoff_kind, :string
    add_column :ai_agent_proposals, :handoff_id, :uuid
    add_column :ai_agent_proposals, :origin_mcp_session_id, :uuid
    add_column :ai_improvement_recommendations, :origin_mcp_session_id, :uuid
  end
end
