# frozen_string_literal: true

FactoryBot.define do
  factory :shared_prompt_template, class: "Shared::PromptTemplate" do
    association :account
    association :created_by, factory: :user
    sequence(:name) { |n| "Prompt Template #{n}" }
    sequence(:slug) { |n| "prompt-template-#{n}" }
    category { "custom" }
    domain { "general" }
    content { "You are a helpful assistant. {{ context }}" }
    description { "A test prompt template" }
    version { 1 }
    is_active { true }
    is_system { false }
    variables do
      [
        { "name" => "context", "type" => "string", "required" => false, "description" => "Context for the prompt" }
      ]
    end
    metadata { {} }

    trait :review do
      category { "review" }
      name { "Code Review Template" }
      content { "Review the following code:\n\n{{ code }}\n\nProvide feedback on: {{ aspects }}" }
      variables do
        [
          { "name" => "code", "type" => "string", "required" => true },
          { "name" => "aspects", "type" => "string", "required" => false, "default" => "quality, security, performance" }
        ]
      end
    end

    trait :implement do
      category { "implement" }
      name { "Implementation Template" }
      content { "Implement the following feature:\n\n{{ requirements }}\n\nLanguage: {{ language }}" }
    end

    trait :security do
      category { "security" }
      name { "Security Analysis Template" }
      content { "Analyze the following for security vulnerabilities:\n\n{{ target }}" }
    end

    trait :deploy do
      category { "deploy" }
      name { "Deployment Template" }
      content { "Generate deployment configuration for:\n\n{{ service_name }}" }
    end

    trait :docs do
      category { "docs" }
      name { "Documentation Template" }
      content { "Generate documentation for:\n\n{{ subject }}" }
    end

    trait :for_ai_workflow do
      domain { "ai_workflow" }
    end

    trait :for_cicd do
      domain { "cicd" }
    end

    trait :system_template do
      is_system { true }
    end

    trait :inactive do
      is_active { false }
    end

    trait :with_versions do
      after(:create) do |template|
        2.times do |i|
          template.create_version(
            "Updated content v#{i + 2}. {{ context }}",
            created_by: template.created_by
          )
        end
      end
    end
  end
end
