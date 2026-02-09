# frozen_string_literal: true

FactoryBot.define do
  factory :ai_team_channel, class: "Ai::TeamChannel" do
    association :agent_team, factory: :ai_agent_team
    sequence(:name) { |n| "Channel #{n}" }
    channel_type { "broadcast" }
    description { "A team channel" }
    participant_roles { [] }
    message_schema { {} }
    routing_rules { {} }
    is_persistent { true }
    metadata { {} }

    trait :broadcast do
      channel_type { "broadcast" }
    end

    trait :direct do
      channel_type { "direct" }
    end

    trait :topic do
      channel_type { "topic" }
    end

    trait :task do
      channel_type { "task" }
    end

    trait :escalation do
      channel_type { "escalation" }
    end

    trait :with_retention do
      message_retention_hours { 24 }
    end

    trait :non_persistent do
      is_persistent { false }
    end
  end
end
