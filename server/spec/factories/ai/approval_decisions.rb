# frozen_string_literal: true

FactoryBot.define do
  factory :ai_approval_decision, class: "Ai::ApprovalDecision" do
    association :approval_request, factory: :ai_approval_request
    association :approver, factory: :user
    step_number { 0 }
    decision { "approved" }
    comments { "Looks good" }
    conditions { {} }

    trait :rejected do
      decision { "rejected" }
      comments { "Needs changes" }
    end

    trait :delegated do
      decision { "delegated" }
    end

    trait :abstained do
      decision { "abstained" }
    end
  end
end
