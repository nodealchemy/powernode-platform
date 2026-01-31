# frozen_string_literal: true

FactoryBot.define do
  factory :ai_a2a_task_event, class: "Ai::A2aTaskEvent" do
    association :a2a_task, factory: :ai_a2a_task
    event_type { 'status_change' }
    data { { 'old_status' => 'pending', 'new_status' => 'active' } }

    trait :status_change do
      event_type { 'status_change' }
      data { { 'old_status' => 'pending', 'new_status' => 'active' } }
    end

    trait :artifact_added do
      event_type { 'artifact_added' }
      data do
        {
          'artifact_id' => SecureRandom.uuid,
          'name' => 'result.json',
          'mime_type' => 'application/json'
        }
      end
    end

    trait :progress do
      event_type { 'progress' }
      data { { 'current' => 5, 'total' => 10, 'message' => 'Processing...' } }
    end

    trait :message do
      event_type { 'message' }
      data do
        {
          'role' => 'assistant',
          'content' => 'Working on your request...'
        }
      end
    end

    trait :error do
      event_type { 'error' }
      data { { 'error_type' => 'timeout', 'message' => 'Task timed out' } }
    end
  end
end
