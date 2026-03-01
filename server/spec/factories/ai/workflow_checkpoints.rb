# frozen_string_literal: true

FactoryBot.define do
  factory :ai_workflow_checkpoint, class: "Ai::WorkflowCheckpoint" do
    association :workflow_run, factory: :ai_workflow_run
    checkpoint_id { SecureRandom.uuid }
    checkpoint_type { "node_completion" }
    node_id { SecureRandom.uuid }
    sequence(:sequence_number)
    workflow_state { {} }
    execution_context { {} }
    variable_snapshot { {} }
    metadata { {} }

    trait :manual do
      checkpoint_type { "manual" }
    end

    trait :with_description do
      description { "Checkpoint after processing stage" }
    end
  end
end
