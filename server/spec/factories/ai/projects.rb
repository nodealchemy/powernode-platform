# frozen_string_literal: true

FactoryBot.define do
  factory :ai_project, class: "Ai::Project" do
    account
    sequence(:name) { |n| "Project #{n}" }
    status { "active" }

    trait :paused do
      status { "paused" }
    end

    trait :archived do
      status { "archived" }
    end
  end
end
