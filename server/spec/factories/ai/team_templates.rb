# frozen_string_literal: true

FactoryBot.define do
  factory :ai_team_template, class: "Ai::TeamTemplate" do
    account
    sequence(:name) { |n| "Team Template #{n}" }
    sequence(:slug) { |n| "team-template-#{n}" }
    description { Faker::Lorem.sentence }
    team_topology { "hierarchical" }
    role_definitions { [] }
    channel_definitions { [] }
    default_config { {} }
    workflow_pattern { {} }
    tags { [] }
    is_public { false }
    is_system { false }
    usage_count { 0 }

    trait :public_template do
      is_public { true }
    end

    trait :system_template do
      is_system { true }
      account { nil }
    end

    trait :flat do
      team_topology { "flat" }
    end
  end
end
