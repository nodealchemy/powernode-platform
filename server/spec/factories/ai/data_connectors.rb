# frozen_string_literal: true

FactoryBot.define do
  factory :ai_data_connector, class: "Ai::DataConnector" do
    account
    association :knowledge_base, factory: :ai_knowledge_base
    sequence(:name) { |n| "Data Connector #{n}" }
    connector_type { "github" }
    status { "active" }
    connection_config { {} }
    sync_config { {} }
    last_sync_result { {} }
    documents_synced { 0 }
    sync_errors { 0 }

    trait :notion do
      connector_type { "notion" }
    end

    trait :paused do
      status { "paused" }
    end

    trait :error do
      status { "error" }
      sync_errors { 3 }
    end
  end
end
