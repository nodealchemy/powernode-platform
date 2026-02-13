# frozen_string_literal: true

FactoryBot.define do
  factory :ai_discovery_result, class: "Ai::DiscoveryResult" do
    account
    scan_id { SecureRandom.uuid }
    scan_type { "full" }
    status { "pending" }
    discovered_agents { [] }
    discovered_connections { [] }
    discovered_tools { [] }
    recommendations { [] }
    agents_found { 0 }
    connections_found { 0 }
    tools_found { 0 }

    trait :completed do
      status { "completed" }
      started_at { 5.minutes.ago }
      completed_at { Time.current }
      agents_found { 3 }
      tools_found { 5 }
    end

    trait :failed do
      status { "failed" }
      error_message { "Scan failed" }
    end
  end
end
