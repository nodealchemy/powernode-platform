# frozen_string_literal: true

FactoryBot.define do
  factory :external_agent do
    account
    sequence(:name) { |n| "External Agent #{n}" }
    description { "An external A2A-compliant agent" }
    agent_card_url { "https://example.com/.well-known/agent-card.json" }
    status { "active" }
    health_status { "healthy" }
    skills { [] }
    capabilities { {} }
    cached_card { {} }
    task_count { 0 }
    success_count { 0 }
    failure_count { 0 }

    trait :with_skills do
      skills do
        [
          { "id" => "workflow.execute", "name" => "Execute Workflow", "description" => "Execute a workflow" },
          { "id" => "data.transform", "name" => "Transform Data", "description" => "Transform data" }
        ]
      end
    end

    trait :with_capabilities do
      capabilities do
        {
          "streaming" => true,
          "pushNotifications" => true
        }
      end
    end

    trait :with_cached_card do
      cached_card do
        {
          "name" => "External Agent",
          "url" => "https://example.com/a2a",
          "version" => "1.0.0",
          "skills" => [
            { "id" => "test.skill", "name" => "Test Skill" }
          ]
        }
      end
      card_cached_at { 10.minutes.ago }
      card_version { "1.0.0" }
    end

    trait :inactive do
      status { "inactive" }
    end

    trait :unhealthy do
      health_status { "unhealthy" }
      health_details { { "error" => "Connection refused" } }
    end

    trait :needs_health_check do
      last_health_check { 10.minutes.ago }
    end

    trait :with_authentication do
      authentication do
        {
          "type" => "bearer",
          "token" => "secret-token"
        }
      end
    end
  end
end
