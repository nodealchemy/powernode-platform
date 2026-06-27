# frozen_string_literal: true

FactoryBot.define do
  factory :ai_campaign, class: "Ai::Campaign" do
    account
    name { "Improve the billing extension" }
    description { "Autonomous improvement campaign" }
    status { "created" }
    decision_authority { "trusted" }
    configuration { {} }
    stop_conditions { {} }

    trait :active do
      status { "active" }
      started_at { Time.current }
    end
  end
end
