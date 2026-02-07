# frozen_string_literal: true

FactoryBot.define do
  factory :ai_trajectory, class: "Ai::Trajectory" do
    account
    sequence(:title) { |n| "Trajectory #{n}" }
    status { "building" }
    trajectory_type { "task_completion" }
    tags { [] }
    metadata { {} }

    trait :building do
      status { "building" }
    end

    trait :completed do
      status { "completed" }
      quality_score { 0.85 }
    end

    trait :archived do
      status { "archived" }
    end
  end
end
