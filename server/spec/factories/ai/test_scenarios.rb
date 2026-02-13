# frozen_string_literal: true

FactoryBot.define do
  factory :ai_test_scenario, class: "Ai::TestScenario" do
    account
    association :sandbox, factory: :ai_sandbox
    sequence(:name) { |n| "Test Scenario #{n}" }
    description { Faker::Lorem.sentence }
    scenario_type { "unit" }
    status { "active" }
    input_data { {} }
    expected_output { {} }
    assertions { [] }
    mock_responses { [] }
    setup_steps { [] }
    teardown_steps { [] }
    tags { [] }
    timeout_seconds { 300 }
    max_retries { 3 }
    retry_count { 0 }
    run_count { 0 }
    pass_count { 0 }
    fail_count { 0 }

    trait :integration do
      scenario_type { "integration" }
    end

    trait :regression do
      scenario_type { "regression" }
    end

    trait :disabled do
      status { "disabled" }
    end

    trait :archived do
      status { "archived" }
    end
  end
end
