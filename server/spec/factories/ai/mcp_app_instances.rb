# frozen_string_literal: true

FactoryBot.define do
  factory :ai_mcp_app_instance, class: "Ai::McpAppInstance" do
    association :mcp_app, factory: :ai_mcp_app
    account { mcp_app.account }
    status { "created" }
    state { {} }
    input_data { {} }
    output_data { {} }

    trait :created_status do
      status { "created" }
    end

    trait :running do
      status { "running" }
      started_at { Time.current }
    end

    trait :completed do
      status { "completed" }
      started_at { 1.hour.ago }
      completed_at { Time.current }
      output_data { { result: "success" } }
    end

    trait :error do
      status { "error" }
      started_at { 1.hour.ago }
      completed_at { Time.current }
      output_data { { error: "Something went wrong" } }
    end

    trait :with_session do
      association :session, factory: :ai_agui_session
    end
  end
end
