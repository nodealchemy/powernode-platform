# frozen_string_literal: true

FactoryBot.define do
  factory :ai_code_review_comment, class: "Ai::CodeReviewComment" do
    association :task_review, factory: :ai_task_review
    content { Faker::Lorem.paragraph }
    file_path { "app/services/example.rb" }
    line_start { 10 }
    line_end { 15 }
    comment_type { "suggestion" }
    category { "code_quality" }
    severity { "warning" }
    resolved { false }
    metadata { {} }

    trait :critical do
      severity { "critical" }
      category { "security" }
    end

    trait :resolved do
      resolved { true }
    end

    trait :with_fix do
      suggested_fix { "def better_method\n  # improved implementation\nend" }
    end
  end
end
