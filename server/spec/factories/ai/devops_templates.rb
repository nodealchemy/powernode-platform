# frozen_string_literal: true

FactoryBot.define do
  factory :ai_devops_template, class: "Ai::DevopsTemplate" do
    association :account
    association :created_by, factory: :user

    sequence(:name) { |n| "DevOps Template #{n}" }
    sequence(:slug) { |n| "devops-template-#{n}" }
    description { "A test DevOps template for AI-powered CI/CD operations" }
    category { "code_quality" }
    template_type { "code_review" }
    status { "draft" }
    visibility { "private" }
    version { "1.0.0" }
    workflow_definition do
      {
        "nodes" => [
          { "id" => "start", "type" => "start", "name" => "Start" },
          { "id" => "review", "type" => "ai_agent", "name" => "Code Review Agent" },
          { "id" => "end", "type" => "end", "name" => "End" }
        ],
        "edges" => [
          { "source" => "start", "target" => "review" },
          { "source" => "review", "target" => "end" }
        ]
      }
    end
    trigger_config { { "event_types" => [ "pull_request", "push" ] } }
    input_schema { { "type" => "object", "properties" => { "repository_url" => { "type" => "string" } } } }
    output_schema { { "type" => "object", "properties" => { "review_summary" => { "type" => "string" } } } }
    variables { [] }
    secrets_required { [] }
    integrations_required { [ "github" ] }
    tags { [ "code-review", "quality" ] }
    is_system { false }
    is_featured { false }
    installation_count { 0 }
    review_count { 0 }

    trait :published do
      status { "published" }
      published_at { Time.current }
    end

    trait :pending_review do
      status { "pending_review" }
    end

    trait :archived do
      status { "archived" }
    end

    trait :deprecated do
      status { "deprecated" }
    end

    trait :public do
      visibility { "public" }
    end

    trait :marketplace do
      visibility { "marketplace" }
      status { "published" }
      published_at { Time.current }
      price_usd { 49.99 }
    end

    trait :team do
      visibility { "team" }
    end

    trait :system do
      is_system { true }
      account { nil }
      created_by { nil }
    end

    trait :featured do
      is_featured { true }
      status { "published" }
      published_at { Time.current }
    end

    trait :popular do
      installation_count { 500 }
      average_rating { 4.7 }
      review_count { 45 }
    end

    trait :security_scan do
      category { "security" }
      template_type { "security_scan" }
      name { "Security Vulnerability Scanner" }
      description { "AI-powered security vulnerability detection" }
      integrations_required { [ "github", "sonarqube" ] }
      tags { [ "security", "vulnerability", "scan" ] }
    end

    trait :test_generation do
      category { "testing" }
      template_type { "test_generation" }
      name { "Automated Test Generator" }
      description { "AI-powered unit test generation" }
      tags { [ "testing", "automation", "unit-tests" ] }
    end

    trait :deployment_validation do
      category { "deployment" }
      template_type { "deployment_validation" }
      name { "Deployment Validator" }
      description { "Pre-deployment validation and risk assessment" }
      tags { [ "deployment", "validation", "risk" ] }
    end

    trait :release_notes do
      category { "release" }
      template_type { "release_notes" }
      name { "Release Notes Generator" }
      description { "Automated release notes generation from commits" }
      tags { [ "release", "documentation", "changelog" ] }
    end

    trait :with_secrets do
      secrets_required { [ "GITHUB_TOKEN", "SONARQUBE_TOKEN" ] }
    end

    trait :with_variables do
      variables do
        [
          { "name" => "target_branch", "type" => "string", "default" => "main" },
          { "name" => "severity_threshold", "type" => "string", "default" => "medium" }
        ]
      end
    end
  end
end
