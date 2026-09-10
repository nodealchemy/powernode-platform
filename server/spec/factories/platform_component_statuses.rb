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

    # The DERIVED verdict is `held` and nothing else is wrong.
    trait :held do
      verdict { Platform::ComponentStatus::HELD }
      conditions { [ { "type" => "Held", "status" => true, "reason" => "Cordoned" } ] }
    end

    # OPERATOR INTENT is present, whatever the verdict is. Combine with :down
    # for the case the L2 ruling exists for: a cordoned node that is also down.
    trait :held_by_intent do
      conditions { [ { "type" => "Held", "status" => true, "reason" => "Cordoned" } ] }
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
