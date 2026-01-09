# frozen_string_literal: true

FactoryBot.define do
  factory :ai_workflow_trigger, class: "Ai::WorkflowTrigger" do
    association :workflow, factory: :ai_workflow

    sequence(:name) { |n| "Test Trigger #{n}" }
    trigger_type { 'manual' }
    status { 'active' }
    is_active { true }
    configuration { { 'type' => 'manual' } }
    conditions { {} }
    metadata { {} }

    trait :webhook do
      trigger_type { 'webhook' }
      configuration do
        {
          'type' => 'webhook',
          'webhook_url' => "https://example.com/webhook/#{SecureRandom.hex(8)}",
          'secret' => SecureRandom.hex(20)
        }
      end
    end

    trait :schedule do
      trigger_type { 'schedule' }
      configuration do
        {
          'type' => 'schedule',
          'cron' => '0 * * * *',
          'timezone' => 'UTC'
        }
      end
    end

    trait :event do
      trigger_type { 'event' }
      configuration do
        {
          'type' => 'event',
          'event_type' => 'git.push',
          'filters' => {}
        }
      end
    end

    trait :paused do
      status { 'paused' }
    end

    trait :disabled do
      status { 'disabled' }
      is_active { false }
    end
  end
end
