# frozen_string_literal: true

FactoryBot.define do
  factory :ai_campaign_proposal, class: "Ai::CampaignProposal" do
    account
    sequence(:title) { |n| "Improve subsystem #{n}" }
    # Sequence the objective so the per-target fingerprint differs across builds in the
    # same account (the [account_id, fingerprint] index is unique).
    sequence(:objective) { |n| "Reduce N+1 queries across the reporting controllers (target #{n})." }
    source { "manual" }
    suggested_workload { "improvement-campaign" }
    decision_authority { "trusted" }
    status { "proposed" }
    configuration { {} }
    evidence { {} }
    # fingerprint is auto-derived by the model's before_validation.

    trait :discovery do
      source { "discovery" }
    end

    trait :queued do
      status { "queued" }
    end

    trait :approved do
      status { "approved" }
    end

    trait :feature do
      suggested_workload { "feature-development" }
    end

    trait :cc_driver do
      suggested_driver { "claude_code" }
    end
  end
end
