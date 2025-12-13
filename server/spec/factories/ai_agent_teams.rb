# frozen_string_literal: true

FactoryBot.define do
  factory :ai_agent_team do
    account
    sequence(:name) { |n| "Agent Team #{n}" }
    description { 'A team of AI agents working together' }
    team_type { 'hierarchical' }
    goal_description { 'Complete complex multi-step tasks through collaboration' }
    coordination_strategy { 'manager_worker' }
    team_config { { max_iterations: 10, timeout_seconds: 300 } }
    status { 'active' }

    trait :hierarchical do
      team_type { 'hierarchical' }
      coordination_strategy { 'manager_worker' }
      description { 'Hierarchical team with manager-worker coordination' }
    end

    trait :mesh do
      team_type { 'mesh' }
      coordination_strategy { 'peer_to_peer' }
      description { 'Mesh team with peer-to-peer coordination' }
    end

    trait :sequential do
      team_type { 'sequential' }
      coordination_strategy { 'manager_worker' }
      description { 'Sequential team executing tasks in order' }
    end

    trait :parallel do
      team_type { 'parallel' }
      coordination_strategy { 'hybrid' }
      description { 'Parallel team executing tasks concurrently' }
    end

    trait :inactive do
      status { 'inactive' }
    end

    trait :archived do
      status { 'archived' }
    end

    trait :with_members do
      transient do
        members_count { 3 }
      end

      after(:create) do |team, evaluator|
        create_list(:ai_agent_team_member, evaluator.members_count, ai_agent_team: team)
      end
    end

    trait :with_lead do
      after(:create) do |team|
        create(:ai_agent_team_member, :lead, ai_agent_team: team)
      end
    end

    trait :content_generation_crew do
      name { 'Content Generation Crew' }
      description { 'Specialized team for generating high-quality content' }
      team_type { 'sequential' }
      goal_description { 'Research, write, and review content pieces' }

      after(:create) do |team|
        account = team.account

        # Create specialized agents for content generation
        researcher = create(:ai_agent, account: account, name: 'Research Agent', agent_type: 'data_analyst')
        writer = create(:ai_agent, account: account, name: 'Writer Agent', agent_type: 'content_generator')
        reviewer = create(:ai_agent, account: account, name: 'Review Agent', agent_type: 'code_assistant')

        # Add members in sequential order
        create(:ai_agent_team_member, :lead,
               ai_agent_team: team,
               ai_agent: researcher,
               role: 'researcher',
               priority_order: 0,
               capabilities: [ 'research', 'fact_checking', 'source_verification' ])

        create(:ai_agent_team_member,
               ai_agent_team: team,
               ai_agent: writer,
               role: 'writer',
               priority_order: 1,
               capabilities: [ 'content_writing', 'seo_optimization', 'tone_adaptation' ])

        create(:ai_agent_team_member,
               ai_agent_team: team,
               ai_agent: reviewer,
               role: 'reviewer',
               priority_order: 2,
               capabilities: [ 'proofreading', 'quality_assurance', 'brand_alignment' ])
      end
    end
  end
end
