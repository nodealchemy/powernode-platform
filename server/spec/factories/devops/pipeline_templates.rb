# frozen_string_literal: true

FactoryBot.define do
  factory :devops_pipeline_template, class: "Devops::PipelineTemplate" do
    association :account
    association :created_by_user, factory: :user

    sequence(:name) { |n| "Pipeline Template #{n}" }
    sequence(:slug) { |n| "pipeline-template-#{n}" }
    description { "A reusable pipeline template for CI/CD workflows" }
    category { "deploy" }
    difficulty_level { "intermediate" }
    status { "draft" }
    version { "1.0.0" }
    timeout_minutes { 30 }

    pipeline_definition do
      {
        "pipeline_type" => "deploy",
        "steps" => [
          {
            "name" => "Build",
            "step_type" => "build",
            "position" => 1,
            "configuration" => { "command" => "npm run build" }
          },
          {
            "name" => "Test",
            "step_type" => "test",
            "position" => 2,
            "configuration" => { "command" => "npm test" }
          },
          {
            "name" => "Deploy",
            "step_type" => "deploy",
            "position" => 3,
            "configuration" => { "target" => "production" }
          }
        ],
        "features" => {},
        "runner_labels" => ["ubuntu-latest"]
      }
    end

    default_variables do
      {
        "NODE_VERSION" => "18",
        "DEPLOY_TARGET" => "production"
      }
    end

    triggers do
      {
        "manual" => true,
        "push" => { "branches" => ["main"] }
      }
    end

    tags { ["nodejs", "deployment", "production"] }
    metadata { {} }

    is_public { false }
    is_featured { false }
    is_system { false }

    rating { 0.0 }
    rating_count { 0 }
    usage_count { 0 }
    install_count { 0 }

    trait :published do
      status { "published" }
      is_public { true }
      published_at { 1.day.ago }
    end

    trait :draft do
      status { "draft" }
      is_public { false }
      published_at { nil }
    end

    trait :archived do
      status { "archived" }
    end

    trait :public do
      is_public { true }
      status { "published" }
      published_at { 1.day.ago }
    end

    trait :featured do
      is_featured { true }
      is_public { true }
      status { "published" }
      published_at { 1.week.ago }
    end

    trait :system do
      is_system { true }
    end

    trait :beginner do
      difficulty_level { "beginner" }
    end

    trait :advanced do
      difficulty_level { "advanced" }
    end

    trait :expert do
      difficulty_level { "expert" }
    end

    trait :review do
      category { "review" }
      pipeline_definition do
        {
          "pipeline_type" => "review",
          "steps" => [
            {
              "name" => "Code Analysis",
              "step_type" => "ai_review",
              "position" => 1,
              "configuration" => { "review_type" => "security" }
            }
          ]
        }
      end
    end

    trait :security do
      category { "security" }
      pipeline_definition do
        {
          "pipeline_type" => "security",
          "steps" => [
            {
              "name" => "Security Scan",
              "step_type" => "security_scan",
              "position" => 1,
              "configuration" => { "scan_type" => "full" }
            }
          ]
        }
      end
    end

    trait :custom do
      category { "custom" }
    end

    trait :highly_rated do
      rating { 4.8 }
      rating_count { 50 }
    end

    trait :popular do
      usage_count { 500 }
      install_count { 200 }
    end

    trait :with_source_pipeline do
      association :source_pipeline, factory: :devops_pipeline
    end
  end
end
