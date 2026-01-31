# frozen_string_literal: true

FactoryBot.define do
  factory :ai_a2a_task, class: "Ai::A2aTask" do
    account
    association :from_agent, factory: :ai_agent
    association :to_agent, factory: :ai_agent
    task_id { SecureRandom.uuid }
    status { 'pending' }
    input { { 'message' => 'Test input' } }
    output { {} }
    artifacts { [] }
    metadata { {} }
    sequence_number { 0 }

    trait :active do
      status { 'active' }
      started_at { Time.current }
    end

    trait :completed do
      status { 'completed' }
      started_at { 5.minutes.ago }
      completed_at { Time.current }
      output { { 'result' => 'Task completed successfully' } }
    end

    trait :failed do
      status { 'failed' }
      started_at { 5.minutes.ago }
      completed_at { Time.current }
      error_message { 'Task execution failed due to timeout' }
    end

    trait :cancelled do
      status { 'cancelled' }
      started_at { 5.minutes.ago }
      completed_at { Time.current }
      error_message { 'Task was cancelled by user' }
    end

    trait :input_required do
      status { 'input_required' }
      started_at { Time.current }
    end

    trait :with_workflow_run do
      association :workflow_run, factory: :ai_workflow_run
    end

    trait :with_artifacts do
      artifacts do
        [
          {
            'artifact_id' => SecureRandom.uuid,
            'name' => 'output.json',
            'mime_type' => 'application/json',
            'data' => { 'key' => 'value' }
          }
        ]
      end
    end

    trait :with_complex_input do
      input do
        {
          'message' => {
            'role' => 'user',
            'parts' => [
              { 'type' => 'text', 'text' => 'Analyze this data' },
              { 'type' => 'data', 'data' => { 'values' => [1, 2, 3] } }
            ]
          },
          'context' => {
            'task_type' => 'analysis',
            'priority' => 'high'
          }
        }
      end
    end
  end
end
