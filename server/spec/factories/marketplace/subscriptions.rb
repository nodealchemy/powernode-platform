# frozen_string_literal: true

FactoryBot.define do
  factory :marketplace_subscription, class: 'Marketplace::Subscription' do
    association :account
    association :app, factory: :marketplace_definition
    association :plan, factory: :marketplace_plan
    status { 'active' }
    subscribed_at { Time.current }
    tier { nil }
    configuration { {} }
    usage_metrics { {} }
    metadata { {} }

    trait :active do
      status { 'active' }
    end

    trait :paused do
      status { 'paused' }
      cancelled_at { Time.current }
    end

    trait :cancelled do
      status { 'cancelled' }
      cancelled_at { Time.current }
    end

    trait :expired do
      status { 'expired' }
      cancelled_at { Time.current }
    end

    trait :with_tier do
      tier { 'standard' }
    end

    trait :free_tier do
      tier { 'free' }
    end

    trait :premium_tier do
      tier { 'premium' }
    end

    trait :enterprise_tier do
      tier { 'enterprise' }
    end

    trait :with_configuration do
      configuration { { 'feature_flags' => { 'advanced' => true } } }
    end

    trait :with_usage_metrics do
      usage_metrics do
        {
          'api_calls' => { 'value' => 50, 'recorded_at' => Time.current.iso8601 },
          'storage_used' => { 'value' => 100, 'recorded_at' => Time.current.iso8601 }
        }
      end
    end

    trait :due_for_billing do
      next_billing_at { 1.day.ago }
    end

    trait :expiring_soon do
      next_billing_at { 3.days.from_now }
    end

    # Polymorphic subscription for workflow templates
    trait :for_workflow_template do
      subscribable_type { 'Ai::WorkflowTemplate' }
      app { nil }
      plan { nil }
    end

    # Polymorphic subscription for pipeline templates
    trait :for_pipeline_template do
      subscribable_type { 'Devops::PipelineTemplate' }
      app { nil }
      plan { nil }
    end

    # Alias for backward compatibility
    factory :app_subscription, class: 'Marketplace::Subscription'
  end
end
