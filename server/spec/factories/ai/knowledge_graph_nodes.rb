# frozen_string_literal: true

FactoryBot.define do
  factory :ai_knowledge_graph_node, class: "Ai::KnowledgeGraphNode" do
    account
    sequence(:name) { |n| "Entity #{n}" }
    node_type { "entity" }
    entity_type { "technology" }
    description { Faker::Lorem.sentence }
    properties { {} }
    confidence { 1.0 }
    mention_count { 1 }
    status { "active" }
    metadata { {} }
    last_seen_at { Time.current }

    trait :concept do
      node_type { "concept" }
      entity_type { nil }
      sequence(:name) { |n| "Concept #{n}" }
    end

    trait :relation_node do
      node_type { "relation" }
      entity_type { nil }
      sequence(:name) { |n| "Relation #{n}" }
    end

    trait :attribute_node do
      node_type { "attribute" }
      entity_type { nil }
      sequence(:name) { |n| "Attribute #{n}" }
    end

    trait :person do
      entity_type { "person" }
      sequence(:name) { |n| "Person #{n}" }
    end

    trait :organization do
      entity_type { "organization" }
      sequence(:name) { |n| "Organization #{n}" }
    end

    trait :merged do
      status { "merged" }
      association :merged_into, factory: :ai_knowledge_graph_node
    end

    trait :archived do
      status { "archived" }
    end

    trait :with_knowledge_base do
      association :knowledge_base, factory: :ai_knowledge_base
    end
  end
end
