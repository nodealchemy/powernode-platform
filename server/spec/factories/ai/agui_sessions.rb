# frozen_string_literal: true

FactoryBot.define do
  factory :ai_agui_session, class: "Ai::AguiSession" do
    account
    sequence(:thread_id) { |n| "thread_#{SecureRandom.hex(8)}_#{n}" }
    status { "idle" }
    state { {} }
    messages { [] }
    tools { [] }
    context { [] }
    capabilities { {} }
    sequence_number { 0 }

    trait :idle do
      status { "idle" }
    end

    trait :running do
      status { "running" }
      run_id { "run_#{SecureRandom.hex(12)}" }
      started_at { Time.current }
    end

    trait :completed do
      status { "completed" }
      run_id { "run_#{SecureRandom.hex(12)}" }
      started_at { 1.hour.ago }
      completed_at { Time.current }
    end

    trait :error do
      status { "error" }
      run_id { "run_#{SecureRandom.hex(12)}" }
      started_at { 1.hour.ago }
      completed_at { Time.current }
    end

    trait :cancelled do
      status { "cancelled" }
      run_id { "run_#{SecureRandom.hex(12)}" }
      started_at { 1.hour.ago }
      completed_at { Time.current }
    end

    trait :with_user do
      user
    end

    trait :with_tools do
      tools { [{ name: "calculator", description: "Math operations" }] }
    end

    trait :expired do
      expires_at { 1.hour.ago }
    end
  end
end
