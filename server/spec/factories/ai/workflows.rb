# frozen_string_literal: true

FactoryBot.define do
  factory :ai_workflow, class: "Ai::Workflow" do
    association :account
    association :creator, factory: :user

    sequence(:name) { |n| "Test Workflow #{n}" }
    sequence(:slug) { |n| "test-workflow-#{n}" }
    description { 'A test AI workflow' }
    status { 'draft' }
    version { '1.0.0' }
    visibility { 'private' }
    is_active { true }
    is_template { false }
    configuration { { 'execution_mode' => 'sequential', 'max_execution_time' => 3600 } }
    metadata { {} }

    trait :active do
      status { 'active' }
    end

    trait :paused do
      status { 'paused' }
    end

    trait :archived do
      status { 'archived' }
    end

    trait :template do
      is_template { true }
      visibility { 'public' }
      template_category { 'automation' }
      description { 'A template workflow for testing' }
    end

    trait :with_simple_chain do
      after(:create) do |workflow|
        start_node = create(:ai_workflow_node, :start_node, workflow: workflow)
        agent_node = create(:ai_workflow_node, :ai_agent, workflow: workflow, name: 'Process Agent')
        end_node = create(:ai_workflow_node, :end_node, workflow: workflow)

        # Create chain: start → agent → end
        create(:ai_workflow_edge,
               workflow: workflow,
               source_node_id: start_node.node_id,
               target_node_id: agent_node.node_id)
        create(:ai_workflow_edge,
               workflow: workflow,
               source_node_id: agent_node.node_id,
               target_node_id: end_node.node_id)
      end
    end

    trait :with_variables do
      after(:create) do |workflow|
        create(:ai_workflow_variable, :string_type, workflow: workflow, name: 'input_text')
        create(:ai_workflow_variable, :number_type, workflow: workflow, name: 'max_tokens')
      end
    end

    trait :with_parallel_execution do
      status { 'active' }
      configuration { { 'execution_mode' => 'parallel', 'max_execution_time' => 3600 } }

      after(:create) do |workflow|
        start_node = create(:ai_workflow_node, :start_node, workflow: workflow)
        agent1 = create(:ai_workflow_node, :ai_agent, workflow: workflow, name: 'Agent 1')
        agent2 = create(:ai_workflow_node, :ai_agent, workflow: workflow, name: 'Agent 2')
        end_node = create(:ai_workflow_node, :end_node, workflow: workflow)

        # Parallel edges from start to both agents
        create(:ai_workflow_edge, workflow: workflow,
               source_node_id: start_node.node_id, target_node_id: agent1.node_id)
        create(:ai_workflow_edge, workflow: workflow,
               source_node_id: start_node.node_id, target_node_id: agent2.node_id)

        # Both agents to end
        create(:ai_workflow_edge, workflow: workflow,
               source_node_id: agent1.node_id, target_node_id: end_node.node_id)
        create(:ai_workflow_edge, workflow: workflow,
               source_node_id: agent2.node_id, target_node_id: end_node.node_id)
      end
    end

    trait :with_conditional_branch do
      status { 'active' }
      configuration { { 'execution_mode' => 'sequential', 'max_execution_time' => 3600 } }

      after(:create) do |workflow|
        start_node = create(:ai_workflow_node, :start_node, workflow: workflow)
        condition_node = create(:ai_workflow_node, :condition, workflow: workflow)
        true_branch = create(:ai_workflow_node, :ai_agent, workflow: workflow, name: 'True Branch')
        false_branch = create(:ai_workflow_node, :ai_agent, workflow: workflow, name: 'False Branch')
        end_node = create(:ai_workflow_node, :end_node, workflow: workflow)

        # Start to condition
        create(:ai_workflow_edge, workflow: workflow,
               source_node_id: start_node.node_id, target_node_id: condition_node.node_id)

        # Conditional branches
        create(:ai_workflow_edge, :conditional, workflow: workflow,
               source_node_id: condition_node.node_id, target_node_id: true_branch.node_id)
        create(:ai_workflow_edge, workflow: workflow,
               source_node_id: condition_node.node_id, target_node_id: false_branch.node_id)

        # Both branches to end
        create(:ai_workflow_edge, workflow: workflow,
               source_node_id: true_branch.node_id, target_node_id: end_node.node_id)
        create(:ai_workflow_edge, workflow: workflow,
               source_node_id: false_branch.node_id, target_node_id: end_node.node_id)
      end
    end
  end
end
