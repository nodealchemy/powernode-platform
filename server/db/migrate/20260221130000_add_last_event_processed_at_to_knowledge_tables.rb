# frozen_string_literal: true

class AddLastEventProcessedAtToKnowledgeTables < ActiveRecord::Migration[8.0]
  def change
    add_column :ai_compound_learnings, :last_event_processed_at, :datetime
    add_column :ai_agent_short_term_memories, :last_event_processed_at, :datetime
    add_column :ai_knowledge_graph_nodes, :last_event_processed_at, :datetime
    add_column :ai_shared_knowledges, :last_event_processed_at, :datetime

    add_index :ai_compound_learnings, :last_event_processed_at
    add_index :ai_agent_short_term_memories, :last_event_processed_at
    add_index :ai_knowledge_graph_nodes, :last_event_processed_at
    add_index :ai_shared_knowledges, :last_event_processed_at
  end
end
