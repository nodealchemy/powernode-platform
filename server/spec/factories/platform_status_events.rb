# frozen_string_literal: true

FactoryBot.define do
  factory :platform_status_event, class: "Platform::StatusEvent" do
    association :account
    component_kind { "fake_kind" }
    sequence(:component_ref) { |n| "component-#{n}" }
    kind { Platform::StatusEvent::KIND_STATUS_CHANGED }
    from_verdict { Platform::ComponentStatus::OK }
    to_verdict { Platform::ComponentStatus::DEGRADED }
    occurred_at { Time.current }

    # A process-wide component has no tenant (design §4.4).
    trait :shared do
      account { nil }
    end

    # No previous verdict: the component had never been seen before.
    trait :first_sighting do
      from_verdict { nil }
    end

    trait :down do
      kind { Platform::StatusEvent::KIND_COMPONENT_DOWN }
      to_verdict { Platform::ComponentStatus::DOWN }
    end
  end
end
