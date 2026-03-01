# frozen_string_literal: true

FactoryBot.define do
  factory :ai_task_review, class: "Ai::TaskReview" do
    account
    association :team_task, factory: :ai_team_task
    review_id { SecureRandom.uuid }
    review_mode { "blocking" }
    status { "pending" }
    findings { [] }
    metadata { {} }
    code_suggestions { {} }
    completeness_checks { {} }
    diff_analysis { {} }
    file_comments { {} }
    revision_count { 0 }

    trait :approved do
      status { "approved" }
      quality_score { 0.9 }
      approval_notes { "Looks good" }
    end

    trait :rejected do
      status { "rejected" }
      quality_score { 0.4 }
      rejection_reason { "Does not meet quality standards" }
    end

    trait :shadow do
      review_mode { "shadow" }
    end
  end
end
