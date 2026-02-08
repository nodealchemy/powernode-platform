# frozen_string_literal: true

FactoryBot.define do
  factory :ai_agent_connection, class: "Ai::AgentConnection" do
    association :account
    connection_type { 'a2a_communication' }
    source_type { 'Ai::Agent' }
    source_id { SecureRandom.uuid }
    target_type { 'Ai::Agent' }
    target_id { SecureRandom.uuid }
    status { 'active' }
    strength { 1.0 }
    metadata { {} }

    trait :team_membership do
      connection_type { 'team_membership' }
    end

    trait :mcp_tool_usage do
      connection_type { 'mcp_tool_usage' }
      target_type { 'Mcp::Server' }
    end

    trait :a2a_communication do
      connection_type { 'a2a_communication' }
    end

    trait :shared_memory do
      connection_type { 'shared_memory' }
    end

    trait :inactive do
      status { 'inactive' }
    end
  end
end
