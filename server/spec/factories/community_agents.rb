# frozen_string_literal: true

FactoryBot.define do
  factory :community_agent do
    association :owner_account, factory: :account
    association :agent, factory: :ai_agent
    sequence(:name) { |n| "Community Agent #{n}" }
    description { 'A community-published AI agent for task automation' }
    endpoint_url { 'https://agent.example.com/.well-known/agent.json' }
    visibility { 'public' }
    status { 'active' }
    protocol_version { '0.3' }
    verified { false }
    federated { false }
    task_count { 0 }
    success_count { 0 }
    failure_count { 0 }
    avg_rating { 0.0 }
    rating_count { 0 }
    capabilities do
      {
        'streaming' => true,
        'fileProcessing' => false,
        'webSearch' => false
      }
    end
    authentication do
      {
        'schemes' => [ 'bearer' ]
      }
    end
    category { 'automation' }
    tags { [ 'ai', 'agent' ] }

    trait :public do
      visibility { 'public' }
    end

    trait :unlisted do
      visibility { 'unlisted' }
    end

    trait :active do
      status { 'active' }
    end

    trait :suspended do
      status { 'suspended' }
    end

    trait :deprecated do
      status { 'deprecated' }
    end

    trait :verified do
      verified { true }
    end

    trait :federated do
      federated { true }
      federation_key { SecureRandom.hex(32) }
    end

    trait :popular do
      task_count { 1000 }
      avg_rating { 4.5 }
      rating_count { 100 }
    end

    trait :highly_rated do
      avg_rating { 4.8 }
      rating_count { 50 }
    end

    trait :with_ratings do
      after(:create) do |agent|
        create_list(:community_agent_rating, 5, community_agent: agent)
        agent.refresh_rating!
      end
    end

    trait :code_analysis do
      name { 'Code Analyzer' }
      description { 'Analyzes code for bugs, security issues, and improvements' }
      category { 'analysis' }
      tags { [ 'code', 'analysis', 'security' ] }
      capabilities do
        {
          'streaming' => true,
          'fileProcessing' => true,
          'gitIntegration' => true
        }
      end
    end

    trait :data_processing do
      name { 'Data Processor' }
      description { 'Processes and transforms data files' }
      category { 'automation' }
      tags { [ 'data', 'etl', 'processing' ] }
      capabilities do
        {
          'streaming' => true,
          'fileProcessing' => true,
          'batchProcessing' => true
        }
      end
    end
  end
end
