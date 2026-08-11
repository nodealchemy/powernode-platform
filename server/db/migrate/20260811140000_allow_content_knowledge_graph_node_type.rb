# frozen_string_literal: true

# IMP-bfc06c7663ce. Content nodes (pages, KB articles) get their OWN node_type
# rather than sharing "entity" with skills, agents and teams.
#
# Why a distinct type and not just a naming convention: the partial unique index
# index_ai_kg_nodes_unique_active is on (account_id, name, node_type) WHERE
# status = 'active'. Free-form page TITLES sharing node_type "entity" put them in
# the same uniqueness slot as skill names — a page titled like a skill made the
# skill silently lose its graph node (the create violated the index and a rescue
# swallowed it). Keying content under its own node_type makes that collision
# structurally impossible at exactly the column the index enforces, instead of
# widening the index and legitimising same-named entities everywhere.
#
# This WIDENS the allowed set, so every existing row already satisfies the new
# constraint; the validating scan is over a ~90k-row table and is cheap. Note
# entity_type carries no check constraint, so registering "page"/"article" there
# is a model-only change — this migration is only about node_type.
class AllowContentKnowledgeGraphNodeType < ActiveRecord::Migration[8.0]
  WITHOUT = %w[entity concept relation attribute code_entity].freeze
  WITH = (WITHOUT + %w[content]).freeze
  CONSTRAINT = "check_ai_kg_node_type"

  def up
    swap_node_type_constraint(WITH)
  end

  # Reversible only while no content nodes exist; if any have been written the
  # re-added constraint would reject them, which is the correct loud failure.
  def down
    swap_node_type_constraint(WITHOUT)
  end

  private

  def swap_node_type_constraint(types)
    remove_check_constraint :ai_knowledge_graph_nodes, name: CONSTRAINT
    list = types.map { |t| "'#{t}'::character varying::text" }.join(", ")
    add_check_constraint :ai_knowledge_graph_nodes,
                         "node_type::text = ANY (ARRAY[#{list}])", name: CONSTRAINT
  end
end
