# frozen_string_literal: true

FactoryBot.define do
  factory :ai_campaign_land, class: "Ai::CampaignLand" do
    account
    association :campaign, factory: :ai_campaign
    sequence(:source_branch) { |n| "campaign/feature-#{n}" }
    target_branch { "develop" }
    status { "pending_approval" }

    # Terminal outcomes — accepted vs the failure terminals (see
    # Ai::CampaignLand::TERMINAL_STATUSES). "parked" is non-terminal (re-queueable).
    trait :landed do
      status { "landed" }
      completed_at { Time.current }
    end

    trait :rejected do
      status { "rejected" }
      error_message { "operator rejected" }
      completed_at { Time.current }
    end

    trait :failed do
      status { "failed" }
      error_message { "merge failed" }
      completed_at { Time.current }
    end

    trait :rolled_back do
      status { "rolled_back" }
      completed_at { Time.current }
    end

    trait :parked do
      status { "parked" }
      parked_reason { "merge conflict" }
      parked_at { Time.current }
    end
  end
end
