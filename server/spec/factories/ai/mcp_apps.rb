# frozen_string_literal: true

FactoryBot.define do
  factory :ai_mcp_app, class: "Ai::McpApp" do
    account
    sequence(:name) { |n| "MCP App #{n}" }
    description { "A test MCP application" }
    app_type { "custom" }
    status { "draft" }
    html_content { "<div>Hello World</div>" }
    csp_policy { {} }
    sandbox_config { {} }
    input_schema { {} }
    output_schema { {} }
    metadata { {} }
    version { "1.0.0" }

    trait :draft do
      status { "draft" }
    end

    trait :published do
      status { "published" }
    end

    trait :archived do
      status { "archived" }
    end

    trait :custom do
      app_type { "custom" }
    end

    trait :template do
      app_type { "template" }
    end

    trait :system do
      app_type { "system" }
    end

    trait :with_schema do
      input_schema do
        {
          "type" => "object",
          "required" => ["name"],
          "properties" => {
            "name" => { "type" => "string" },
            "count" => { "type" => "integer" }
          }
        }
      end
      output_schema do
        {
          "type" => "object",
          "properties" => {
            "result" => { "type" => "string" }
          }
        }
      end
    end

    trait :with_csp do
      csp_policy do
        {
          "script-src" => "'self'",
          "style-src" => "'self' 'unsafe-inline'"
        }
      end
    end
  end
end
