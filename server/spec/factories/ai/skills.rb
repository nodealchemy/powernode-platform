# frozen_string_literal: true

FactoryBot.define do
  factory :ai_skill, class: "Ai::Skill" do
    account
    sequence(:name) { |n| "Skill #{n}" }
    sequence(:slug) { |n| "skill-#{n}" }
    description { Faker::Lorem.sentence }
    category { "general" }
    status { "active" }
    version { "1.0.0" }
    is_enabled { true }
    is_system { false }
    commands { [] }
    tags { [] }
    activation_rules { {} }
    metadata { {} }
    usage_count { 0 }

    trait :system_skill do
      is_system { true }
    end

    trait :disabled do
      is_enabled { false }
    end

    trait :with_commands do
      commands do
        [
          { "name" => "execute", "description" => "Execute the skill" },
          { "name" => "configure", "description" => "Configure skill settings" }
        ]
      end
    end
  end
end
