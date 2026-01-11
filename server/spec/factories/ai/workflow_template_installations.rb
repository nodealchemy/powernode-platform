# frozen_string_literal: true

# Factory for workflow template subscriptions (using Marketplace::Subscription)
# This replaces the deprecated Ai::WorkflowTemplateInstallation model
FactoryBot.define do
  factory :workflow_template_subscription, class: "Marketplace::Subscription" do
    association :account
    association :subscribable, factory: :ai_workflow_template
    status { "active" }
    subscribed_at { Time.current }
    tier { "standard" }
    configuration { {} }
    usage_metrics { {} }
    metadata do
      {
        "template_version" => "1.0.0",
        "installation_method" => "template_marketplace",
        "installation_source" => "web_ui",
        "timestamp" => Time.current.iso8601
      }
    end

    trait :with_workflow do
      transient do
        workflow { nil }
      end

      after(:create) do |subscription, evaluator|
        workflow = evaluator.workflow || create(:ai_workflow, account: subscription.account)
        subscription.update!(
          metadata: subscription.metadata.merge(
            "workflow_id" => workflow.id,
            "subscribed_by_user_id" => subscription.account.users.first&.id
          )
        )
      end
    end

    trait :with_customizations do
      configuration do
        {
          "workflow" => {
            "name" => "Customized Workflow Name",
            "configuration" => {
              "max_execution_time" => 7200,
              "notification_settings" => {
                "email" => "custom@example.com"
              }
            }
          }
        }
      end
    end

    trait :outdated do
      metadata do
        {
          "template_version" => "1.0.0",
          "installation_method" => "template_marketplace"
        }
      end
      # The subscribable template should have version "2.0.0" for update checks
    end

    trait :paused do
      status { "paused" }
    end

    trait :cancelled do
      status { "cancelled" }
      cancelled_at { 1.day.ago }
    end
  end

  # Alias for backward compatibility with existing tests
  factory :ai_workflow_template_installation, class: "Marketplace::Subscription" do
    association :account
    association :subscribable, factory: :ai_workflow_template
    status { "active" }
    subscribed_at { Time.current }
    tier { "standard" }
    configuration { {} }
    usage_metrics { {} }
    metadata do
      {
        "template_version" => "1.0.0",
        "installation_method" => "template_marketplace",
        "installation_source" => "web_ui",
        "timestamp" => Time.current.iso8601
      }
    end

    transient do
      template { nil }
      workflow { nil }
      installed_by_user { nil }
      template_version { "1.0.0" }
      customizations { {} }
    end

    after(:build) do |subscription, evaluator|
      subscription.subscribable = evaluator.template if evaluator.template
      subscription.configuration = evaluator.customizations if evaluator.customizations.present?
      subscription.metadata = subscription.metadata.merge("template_version" => evaluator.template_version)
    end

    after(:create) do |subscription, evaluator|
      updates = {}
      updates["workflow_id"] = evaluator.workflow.id if evaluator.workflow
      updates["subscribed_by_user_id"] = evaluator.installed_by_user.id if evaluator.installed_by_user
      subscription.update!(metadata: subscription.metadata.merge(updates)) if updates.present?
    end
  end
end
