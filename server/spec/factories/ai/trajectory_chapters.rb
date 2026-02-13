# frozen_string_literal: true

FactoryBot.define do
  factory :ai_trajectory_chapter, class: "Ai::TrajectoryChapter" do
    association :trajectory, factory: :ai_trajectory
    sequence(:chapter_number)
    chapter_type { "action" }
    sequence(:title) { |n| "Chapter #{n}" }
    content { Faker::Lorem.paragraph(sentence_count: 5) }
    reasoning { Faker::Lorem.sentence }
    key_decisions { [] }
    artifacts { [] }
    context_references { [] }
    metadata { {} }

    trait :observation do
      chapter_type { "observation" }
    end

    trait :decision do
      chapter_type { "decision" }
      key_decisions { [{ "decision" => "Chose approach A", "rationale" => "Better performance" }] }
    end

    trait :with_artifacts do
      artifacts { [{ "type" => "code", "path" => "app/services/example.rb" }] }
    end
  end
end
