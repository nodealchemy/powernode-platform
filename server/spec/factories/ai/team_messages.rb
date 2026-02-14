# frozen_string_literal: true

FactoryBot.define do
  factory :ai_team_message, class: "Ai::TeamMessage" do
    team_execution do
      association :ai_team_execution
    end
    message_type { "task_update" }
    content { "Test message content" }
    priority { "normal" }
    requires_response { false }
    structured_content { {} }
    attachments { [] }

    trait :question do
      message_type { "question" }
      requires_response { true }
    end

    trait :answer do
      message_type { "answer" }
    end

    trait :escalation do
      message_type { "escalation" }
      priority { "high" }
    end

    trait :broadcast do
      message_type { "broadcast" }
    end

    trait :urgent do
      priority { "urgent" }
    end

    trait :high_priority do
      priority { "high" }
    end

    trait :read do
      read_at { Time.current }
    end

    trait :responded do
      responded_at { Time.current }
    end
  end
end
