# frozen_string_literal: true

FactoryBot.define do
  factory :devops_integration_template, class: 'Devops::IntegrationTemplate' do
    sequence(:name) { |n| "Test Template #{n}" }
    sequence(:slug) { |n| "test-template-#{n}" }
    integration_type { "rest_api" }
    category { "ci_cd" }
    version { "1.0.0" }
    description { "A test integration template" }
    is_active { true }
    is_public { true }
    is_featured { false }
    usage_count { 0 }
    install_count { 0 }

    configuration_schema do
      {
        "type" => "object",
        "properties" => {
          "api_endpoint" => { "type" => "string" },
          "timeout" => { "type" => "integer", "default" => 30 }
        },
        "required" => [ "api_endpoint" ]
      }
    end

    credential_requirements { {} }
    capabilities { [ "execute", "test" ] }
    input_schema { {} }
    output_schema { {} }
    default_configuration { { "timeout" => 30 } }
    metadata { {} }
    supported_providers { [] }

    trait :github_action do
      integration_type { "github_action" }
      category { "ci_cd" }
      credential_requirements do
        {
          "type" => "github_app",
          "required" => true
        }
      end
      capabilities { [ "execute", "test", "validate" ] }
    end

    trait :webhook do
      integration_type { "webhook" }
      category { "notifications" }
      configuration_schema do
        {
          "type" => "object",
          "properties" => {
            "webhook_url" => { "type" => "string" },
            "method" => { "type" => "string", "enum" => [ "POST", "PUT" ] }
          },
          "required" => [ "webhook_url" ]
        }
      end
    end

    trait :mcp_server do
      integration_type { "mcp_server" }
      category { "deployment" }
    end

    trait :featured do
      is_featured { true }
      is_public { true }
    end

    trait :private do
      is_public { false }
      association :account
    end

    trait :inactive do
      is_active { false }
    end

    trait :popular do
      usage_count { 100 }
      install_count { 50 }
    end

    trait :with_credential_requirements do
      credential_requirements do
        {
          "type" => "api_key",
          "required" => true,
          "scopes" => [ "read", "write" ]
        }
      end
    end
  end
end
