# frozen_string_literal: true

# 019ff21c. index_ai_kg_nodes_on_ai_data_source_id was a PARTIAL index but NOT
# unique, so several knowledge-graph nodes could point at one data source and
# Ai::DataSource#knowledge_graph_node (a bare has_one) returned an ARBITRARY one
# of them — including to #effectiveness_score's kg_confidence term.
#
# WHY UNIQUE ON THE COLUMN ALONE, not partial on status as the skill side is.
# DataSourceGraph::BridgeService#sync_data_source is the only writer of
# ai_data_source_id on a node, and its two branches implement "at most one node
# per data source, TOTAL": if a node exists it is UPDATED and flipped back to
# status "active" (reviving an archived one), and the create branch runs only when
# no node exists at all. One-per-status would therefore be a weaker statement than
# the code already makes. It also matters that a status-scoped read is the wrong
# remedy here: it would send the revive path down the create branch and
# manufacture the duplicate this index closes.
#
# Contrast idx_kg_nodes_unique_active_skill, which IS partial on status because a
# GLOBAL skill legitimately has one node per account and archived duplicates are
# expected there. A data source is never global (ai_data_sources.account_id is NOT
# NULL), so no such fan-out exists.
#
# SAFETY. Verified against the live ops-hub graph before writing this: 0 nodes
# carry an ai_data_source_id and 0 data sources exist, so the predicate matches no
# rows and there is nothing to de-duplicate or back-fill. The build still scans
# ai_knowledge_graph_nodes (~90k rows), which is sub-second on this table — the
# comparable CHECK-constraint swap in 20260811140000 took 0.09s — so a plain
# (non-concurrent) build is used rather than dragging in
# disable_ddl_transaction!. Note migrations auto-apply on deploy here.
class EnforceOneKgNodePerDataSource < ActiveRecord::Migration[8.0]
  OLD_NAME = "index_ai_kg_nodes_on_ai_data_source_id"
  NEW_NAME = "idx_kg_nodes_unique_data_source"
  PREDICATE = "ai_data_source_id IS NOT NULL"

  def up
    remove_index :ai_knowledge_graph_nodes, name: OLD_NAME
    add_index :ai_knowledge_graph_nodes, :ai_data_source_id,
              unique: true, where: PREDICATE, name: NEW_NAME
  end

  # Reversible: drops back to the non-unique partial index. Safe in either
  # direction, since relaxing a constraint cannot conflict with existing rows.
  def down
    remove_index :ai_knowledge_graph_nodes, name: NEW_NAME
    add_index :ai_knowledge_graph_nodes, :ai_data_source_id,
              where: PREDICATE, name: OLD_NAME
  end
end
