# frozen_string_literal: true

FactoryBot.define do
  factory :ai_agent_team_member, class: "Ai::AgentTeamMember" do
    association :team, factory: :ai_agent_team
    association :agent, factory: :ai_agent
    role { 'executor' }
    capabilities { [ 'task_execution', 'data_processing' ] }
    # priority_order is auto-assigned by callback during create
    is_lead { false }
    member_config { { retry_count: 3, timeout_seconds: 60 } }

    trait :lead do
      is_lead { true }
      role { 'manager' }
      capabilities { [ 'team_coordination', 'task_delegation', 'progress_monitoring' ] }
      priority_order { 0 }
    end

    trait :manager do
      role { 'manager' }
      capabilities { [ 'team_coordination', 'task_delegation', 'decision_making' ] }
      priority_order { 0 }
    end

    trait :researcher do
      role { 'researcher' }
      capabilities { [ 'research', 'data_gathering', 'analysis', 'fact_checking' ] }
      priority_order { 1 }
    end

    trait :writer do
      role { 'writer' }
      capabilities { [ 'content_creation', 'writing', 'editing', 'tone_adaptation' ] }
      priority_order { 2 }
    end

    trait :reviewer do
      role { 'reviewer' }
      capabilities { [ 'quality_assurance', 'proofreading', 'validation', 'feedback' ] }
      priority_order { 3 }
    end

    trait :analyst do
      role { 'analyst' }
      capabilities { [ 'data_analysis', 'pattern_recognition', 'reporting', 'insights' ] }
      priority_order { 2 }
    end

    trait :coordinator do
      role { 'coordinator' }
      capabilities { [ 'communication', 'coordination', 'scheduling', 'resource_management' ] }
      priority_order { 1 }
    end

    trait :facilitator do
      role { 'facilitator' }
      capabilities { [ 'communication', 'conflict_resolution', 'consensus_building' ] }
      priority_order { 1 }
    end

    trait :high_priority do
      priority_order { 0 }
    end

    trait :low_priority do
      priority_order { 10 }
    end
  end
end
