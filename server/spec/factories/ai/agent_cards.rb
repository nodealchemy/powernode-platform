# frozen_string_literal: true

FactoryBot.define do
  factory :ai_agent_card, class: "Ai::AgentCard" do
    account
    association :agent, factory: :ai_agent
    sequence(:name) { |n| "Agent Card #{n}" }
    description { Faker::Lorem.paragraph }
    visibility { 'private' }
    status { 'active' }
    protocol_version { '0.3' }
    capabilities do
      {
        'skills' => [
          {
            'id' => 'summarize',
            'name' => 'Summarize Text',
            'description' => 'Summarizes long text into key points'
          }
        ],
        'streaming' => true,
        'push_notifications' => false
      }
    end
    authentication do
      {
        'schemes' => ['bearer']
      }
    end

    trait :published do
      status { 'active' }
      published_at { Time.current }
    end

    trait :deprecated do
      status { 'deprecated' }
    end

    trait :public do
      visibility { 'public' }
    end

    trait :internal do
      visibility { 'internal' }
    end

    trait :with_endpoint do
      endpoint_url { 'https://api.example.com/.well-known/agent.json' }
    end

    trait :with_metrics do
      task_count { 150 }
      success_count { 142 }
      avg_response_time_ms { 1250 }
    end

    trait :with_multiple_skills do
      capabilities do
        {
          'skills' => [
            { 'id' => 'summarize', 'name' => 'Summarize', 'tags' => ['analysis'] },
            { 'id' => 'translate', 'name' => 'Translate', 'tags' => ['transformation'] },
            { 'id' => 'generate', 'name' => 'Generate Content', 'tags' => ['generation'] }
          ],
          'streaming' => true,
          'push_notifications' => true
        }
      end
    end
  end
end
