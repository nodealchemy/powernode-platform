# frozen_string_literal: true

FactoryBot.define do
  factory :plugin_dependency do
    association :plugin
    sequence(:dependency_plugin_id) { |n| "dependency-plugin-#{n}" }
    is_required { true }
    version_constraint { ">= 1.0.0" }

    trait :optional do
      is_required { false }
    end

    trait :required do
      is_required { true }
    end

    trait :exact_version do
      version_constraint { "= 1.0.0" }
    end

    trait :no_constraint do
      version_constraint { nil }
    end
  end
end
