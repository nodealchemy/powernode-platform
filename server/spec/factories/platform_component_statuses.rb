# frozen_string_literal: true

FactoryBot.define do
  factory :platform_component_status, class: "Platform::ComponentStatus" do
    association :account
    component_kind { "fake_kind" }
    sequence(:component_ref) { |n| "component-#{n}" }
    sequence(:display_name) { |n| "Component #{n}" }
    verdict { Platform::ComponentStatus::OK }
    conditions { [] }
    dependencies { [] }
    last_seen_sweep_at { Time.current }

    # A process-wide kind has no tenant (design §4.4).
    trait :shared do
      account { nil }
    end

    trait :held do
      verdict { Platform::ComponentStatus::HELD }
    end

    trait :down do
      verdict { Platform::ComponentStatus::DOWN }
    end

    trait :degraded do
      verdict { Platform::ComponentStatus::DEGRADED }
    end

    trait :not_measured do
      verdict { Platform::ComponentStatus::NOT_MEASURED }
    end
  end
end
