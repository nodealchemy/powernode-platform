# frozen_string_literal: true

FactoryBot.define do
  factory :ai_skill_proposal, class: "Ai::SkillProposal" do
    account
    association :proposed_by_agent, factory: :ai_agent
    name { "skill-#{Faker::Lorem.unique.word}-#{SecureRandom.hex(3)}" }
    slug { name.parameterize }
    description { Faker::Lorem.paragraph }
    category { "productivity" }
    system_prompt { "You are a helpful assistant for #{name}." }
    status { "draft" }
    trust_tier_at_proposal { "monitored" }
    auto_approved { false }
    commands { [] }
    tags { [] }
    metadata { {} }
    research_report { {} }
    suggested_dependencies { [] }
    overlap_analysis { {} }
    confidence_score { 0.8 }

    trait :proposed do
      status { "proposed" }
      proposed_at { Time.current }
    end

    trait :approved do
      status { "approved" }
      proposed_at { Time.current }
      reviewed_at { Time.current }
      association :reviewed_by, factory: :user
    end

    trait :rejected do
      status { "rejected" }
      proposed_at { Time.current }
      reviewed_at { Time.current }
      rejection_reason { "Overlaps with existing skill" }
      association :reviewed_by, factory: :user
    end

    trait :created do
      status { "created" }
      proposed_at { Time.current }
      reviewed_at { Time.current }
      association :reviewed_by, factory: :user
      association :created_skill, factory: :ai_skill
    end

    trait :auto_approved do
      trust_tier_at_proposal { "autonomous" }
      auto_approved { true }
    end

    trait :with_research do
      research_report do
        {
          "topic" => "test research",
          "sources_searched" => ["knowledge_graph", "knowledge_bases"],
          "existing_skills" => [],
          "suggested_capabilities" => ["capability_1"],
          "confidence_score" => 0.85
        }
      end
    end
  end

  factory :ai_skill_version, class: "Ai::SkillVersion" do
    account
    association :ai_skill, factory: :ai_skill
    version { "1.0.#{SecureRandom.hex(2).to_i(16) % 100}" }
    system_prompt { "You are a versioned assistant." }
    commands { [] }
    tags { [] }
    metadata { {} }
    effectiveness_score { 0.5 }
    usage_count { 0 }
    success_count { 0 }
    failure_count { 0 }
    change_reason { "Initial version" }
    change_type { "manual" }
    is_active { true }
    is_ab_variant { false }
    ab_traffic_pct { 0.0 }

    trait :evolved do
      change_type { "evolution" }
      change_reason { "LLM-assisted improvement" }
    end

    trait :ab_variant do
      is_ab_variant { true }
      is_active { false }
      ab_traffic_pct { 0.2 }
    end

    trait :inactive do
      is_active { false }
    end

    trait :high_performing do
      effectiveness_score { 0.95 }
      usage_count { 100 }
      success_count { 90 }
      failure_count { 10 }
    end
  end

  factory :ai_skill_conflict, class: "Ai::SkillConflict" do
    account
    conflict_type { "duplicate" }
    severity { "medium" }
    status { "detected" }
    association :skill_a, factory: :ai_skill
    association :skill_b, factory: :ai_skill
    similarity_score { 0.95 }
    priority_score { 5.0 }
    auto_resolvable { false }
    detected_at { Time.current }
    resolution_details { {} }

    trait :overlapping do
      conflict_type { "overlapping" }
      similarity_score { 0.8 }
    end

    trait :circular_dependency do
      conflict_type { "circular_dependency" }
      similarity_score { nil }
    end

    trait :stale do
      conflict_type { "stale" }
      skill_b { nil }
      similarity_score { nil }
    end

    trait :orphan do
      conflict_type { "orphan" }
      skill_b { nil }
      similarity_score { nil }
    end

    trait :version_drift do
      conflict_type { "version_drift" }
    end

    trait :auto_resolvable do
      auto_resolvable { true }
    end

    trait :resolved do
      status { "resolved" }
      resolved_at { Time.current }
      association :resolved_by, factory: :user
      resolution_strategy { "merged" }
    end

    trait :dismissed do
      status { "dismissed" }
      resolved_at { Time.current }
      association :resolved_by, factory: :user
    end

    trait :critical do
      severity { "critical" }
    end
  end

  factory :ai_skill_usage_record, class: "Ai::SkillUsageRecord" do
    account
    association :ai_skill, factory: :ai_skill
    association :ai_agent, factory: :ai_agent
    execution_id { SecureRandom.uuid }
    execution_type { "chat" }
    outcome { "success" }
    duration_ms { rand(100..5000) }
    confidence_delta { 0.0 }
    context_summary { "Test execution context" }
    metadata { {} }

    trait :failure do
      outcome { "failure" }
      confidence_delta { -0.05 }
    end

    trait :partial do
      outcome { "partial" }
      confidence_delta { 0.01 }
    end
  end
end
