# frozen_string_literal: true

FactoryBot.define do
  factory :community_agent do
    account
    sequence(:name) { |n| "Community Agent #{n}" }
    description { 'A community-published AI agent for task automation' }
    endpoint_url { 'https://agent.example.com/.well-known/agent.json' }
    visibility { 'public' }
    status { 'active' }
    verified { false }
    federated { false }
    task_count { 0 }
    avg_rating { 0.0 }
    rating_count { 0 }
    agent_card do
      {
        'name' => name,
        'description' => description,
        'version' => '1.0.0',
        'skills' => [
          {
            'id' => 'text.generate',
            'name' => 'Generate Text',
            'description' => 'Generate text content based on prompts'
          },
          {
            'id' => 'data.analyze',
            'name' => 'Analyze Data',
            'description' => 'Analyze and summarize structured data'
          }
        ],
        'capabilities' => {
          'streaming' => true,
          'fileProcessing' => false,
          'webSearch' => false
        },
        'authentication' => {
          'schemes' => ['bearer']
        }
      }
    end
    categories { ['automation', 'general'] }
    tags { ['ai', 'agent'] }

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
      categories { ['development', 'security'] }
      tags { ['code', 'analysis', 'security'] }
      agent_card do
        {
          'name' => 'Code Analyzer',
          'description' => 'Analyzes code for bugs, security issues, and improvements',
          'version' => '1.0.0',
          'skills' => [
            { 'id' => 'code.lint', 'name' => 'Lint Code', 'description' => 'Run linting and style checks' },
            { 'id' => 'code.review', 'name' => 'Code Review', 'description' => 'Review code for issues' },
            { 'id' => 'security.scan', 'name' => 'Security Scan', 'description' => 'Scan for vulnerabilities' }
          ],
          'capabilities' => {
            'streaming' => true,
            'fileProcessing' => true,
            'gitIntegration' => true
          },
          'authentication' => { 'schemes' => ['bearer'] }
        }
      end
    end

    trait :data_processing do
      name { 'Data Processor' }
      description { 'Processes and transforms data files' }
      categories { ['data', 'automation'] }
      tags { ['data', 'etl', 'processing'] }
      agent_card do
        {
          'name' => 'Data Processor',
          'description' => 'Processes and transforms data files',
          'version' => '1.0.0',
          'skills' => [
            { 'id' => 'data.transform', 'name' => 'Transform Data', 'description' => 'Convert between formats' },
            { 'id' => 'data.validate', 'name' => 'Validate Data', 'description' => 'Validate data schemas' },
            { 'id' => 'data.aggregate', 'name' => 'Aggregate Data', 'description' => 'Aggregate and summarize' }
          ],
          'capabilities' => {
            'streaming' => true,
            'fileProcessing' => true,
            'batchProcessing' => true
          },
          'authentication' => { 'schemes' => ['bearer'] }
        }
      end
    end
  end
end
