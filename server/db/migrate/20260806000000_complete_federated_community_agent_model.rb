# frozen_string_literal: true

# IMP-e0cb1dbbff7e — FederationPartner#sync_agent has never successfully
# executed. It assigns two attributes that do not exist on community_agents
# (federation_partner_id, federation_metadata) and never sets two required
# associations (agent, owner_account), so every call raised
# ActiveModel::UnknownAttributeError before writing a row. The trust-survival
# defect the finding described was therefore real in intent but unreachable in
# fact.
#
# Operator decision 2026-08-06: complete the data model rather than retire the
# path. This migration supplies the two missing columns and relaxes the local-
# agent requirement for FEDERATED rows only.
#
# agent_id becomes nullable rather than keeping a placeholder Ai::Agent per
# federated row: a placeholder would be a local agent that nothing can execute,
# and every consumer reading community_agent.agent would have to learn to
# distrust it. The model enforces the real rule instead — a row must carry a
# local agent UNLESS it is federated — so the invariant survives for the local
# catalog while a partner-sourced row is honestly agent-less.
#
# federation_partner_id is a plain uuid column with an index, NOT a
# t.references FK: federation_partners rows are remote-owned and can be revoked
# or destroyed independently, and a hard FK would either block that or cascade
# into the local catalog. The association is declared optional in the model.
class CompleteFederatedCommunityAgentModel < ActiveRecord::Migration[8.1]
  def change
    add_column :community_agents, :federation_partner_id, :uuid
    add_index :community_agents, :federation_partner_id

    add_column :community_agents, :federation_metadata, :jsonb, default: {}, null: false

    change_column_null :community_agents, :agent_id, true
  end
end
