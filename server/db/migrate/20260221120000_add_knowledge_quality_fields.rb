# frozen_string_literal: true

class AddKnowledgeQualityFields < ActiveRecord::Migration[8.0]
  def change
    # CompoundLearning: verification tracking
    change_table :ai_compound_learnings, bulk: true do |t|
      t.datetime :verified_at
      t.uuid :verified_by_id
      t.datetime :disproven_at
      t.uuid :disproven_by_id
      t.datetime :contradiction_resolved_at
      t.text :contradiction_note
    end

    # SharedKnowledge: dynamic quality via ratings
    change_table :ai_shared_knowledges, bulk: true do |t|
      t.integer :rating_sum, default: 0, null: false
      t.integer :rating_count, default: 0, null: false
      t.datetime :last_quality_recalc_at
    end

    # KnowledgeGraphNode: decay support
    change_table :ai_knowledge_graph_nodes, bulk: true do |t|
      t.decimal :decay_rate, precision: 5, scale: 4, default: "0.001"
      t.decimal :quality_score, precision: 5, scale: 4
      t.datetime :last_quality_recalc_at
    end
  end
end
