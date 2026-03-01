# frozen_string_literal: true

FactoryBot.define do
  factory :ai_knowledge_graph_edge, class: "Ai::KnowledgeGraphEdge" do
    account
    association :source_node, factory: :ai_knowledge_graph_node
    association :target_node, factory: :ai_knowledge_graph_node
    relation_type { "related_to" }
    weight { 1.0 }
    confidence { 1.0 }
    properties { {} }
    bidirectional { false }
    status { "active" }
    metadata { {} }

    trait :is_a do
      relation_type { "is_a" }
    end

    trait :has_a do
      relation_type { "has_a" }
    end

    trait :part_of do
      relation_type { "part_of" }
    end

    trait :depends_on do
      relation_type { "depends_on" }
    end

    trait :bidirectional_edge do
      bidirectional { true }
    end

    trait :low_confidence do
      confidence { 0.3 }
    end

    trait :high_weight do
      weight { 0.95 }
    end
  end
end
