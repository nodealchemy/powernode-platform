# frozen_string_literal: true

FactoryBot.define do
  sequence :workflow_version do |n|
    major = (n / 100) % 10
    minor = (n / 10) % 10
    patch = n % 10
    "#{major}.#{minor}.#{patch}"
  end

  factory :ai_workflow do
    account
    creator { association :user, account: account }
    name { "#{Faker::App.name} Workflow #{SecureRandom.hex(4)}" }
    description { Faker::Lorem.paragraph }
    status { 'active' }
    version { generate(:workflow_version) }
    configuration do
      {
        execution_mode: 'sequential',
        max_execution_time: 3600,
        retry_policy: {
          max_retries: 3,
          retry_delay: 5,
          exponential_backoff: true
        },
        error_handling: {
          on_error: 'stop',
          notify_on_failure: true
        }
      }
    end
    metadata do
      {
        created_by: 'system',
        tags: [ 'test', 'automated' ],
        complexity: 'medium'
      }
    end

    trait :inactive do
      status { 'inactive' }
    end

    trait :draft do
      status { 'draft' }
    end

    trait :parallel_execution do
      configuration do
        {
          execution_mode: 'parallel',
          max_execution_time: 1800,
          max_parallel_nodes: 5,
          retry_policy: {
            max_retries: 2,
            retry_delay: 3
          }
        }
      end
    end

    trait :with_simple_chain do
      after(:create) do |workflow|
        # Create shared provider and agent for this workflow to avoid cascading factory creation
        provider = workflow.account.ai_providers.first || create(:ai_provider, account: workflow.account)
        agent = create(:ai_agent, account: workflow.account, ai_provider: provider)

        start_node = create(:ai_workflow_node, :start_node, ai_workflow: workflow)
        # Pass agent_id to prevent after(:build) callback from creating another agent
        ai_agent_node = create(:ai_workflow_node, :ai_agent, ai_workflow: workflow,
                              configuration: { agent_id: agent.id })
        end_node = create(:ai_workflow_node, :end_node, ai_workflow: workflow)

        create(:ai_workflow_edge,
               ai_workflow: workflow,
               source_node_id: start_node.node_id,
               target_node_id: ai_agent_node.node_id)

        create(:ai_workflow_edge,
               ai_workflow: workflow,
               source_node_id: ai_agent_node.node_id,
               target_node_id: end_node.node_id)
      end
    end

    trait :with_complex_flow do
      after(:create) do |workflow|
        # Create nodes
        start_node = create(:ai_workflow_node, :start_node, ai_workflow: workflow)
        condition_node = create(:ai_workflow_node, :condition, ai_workflow: workflow)
        ai_agent_node = create(:ai_workflow_node, :ai_agent, ai_workflow: workflow)
        api_call_node = create(:ai_workflow_node, :api_call, ai_workflow: workflow)
        merge_node = create(:ai_workflow_node, :merge, ai_workflow: workflow)
        webhook_node = create(:ai_workflow_node, :webhook, ai_workflow: workflow)
        end_node = create(:ai_workflow_node, :end_node, ai_workflow: workflow)

        # Create edges
        create(:ai_workflow_edge,
               ai_workflow: workflow,
               source_node_id: start_node.node_id,
               target_node_id: condition_node.node_id)

        # Conditional branches
        create(:ai_workflow_edge,
               ai_workflow: workflow,
               source_node_id: condition_node.node_id,
               target_node_id: ai_agent_node.node_id,
               edge_type: 'conditional',
               is_conditional: true,
               condition: { expression: 'input.type == "ai"' })

        create(:ai_workflow_edge,
               ai_workflow: workflow,
               source_node_id: condition_node.node_id,
               target_node_id: api_call_node.node_id,
               edge_type: 'conditional',
               is_conditional: true,
               condition: { expression: 'input.type == "api"' })

        # Merge branches
        create(:ai_workflow_edge,
               ai_workflow: workflow,
               source_node_id: ai_agent_node.node_id,
               target_node_id: merge_node.node_id)

        create(:ai_workflow_edge,
               ai_workflow: workflow,
               source_node_id: api_call_node.node_id,
               target_node_id: merge_node.node_id)

        # Final flow
        create(:ai_workflow_edge,
               ai_workflow: workflow,
               source_node_id: merge_node.node_id,
               target_node_id: webhook_node.node_id)

        create(:ai_workflow_edge,
               ai_workflow: workflow,
               source_node_id: webhook_node.node_id,
               target_node_id: end_node.node_id)
      end
    end

    trait :with_loop do
      after(:create) do |workflow|
        start_node = create(:ai_workflow_node, :start_node, ai_workflow: workflow)
        loop_node = create(:ai_workflow_node, :loop, ai_workflow: workflow)
        process_node = create(:ai_workflow_node, :ai_agent, ai_workflow: workflow)
        end_node = create(:ai_workflow_node, :end_node, ai_workflow: workflow)

        create(:ai_workflow_edge,
               ai_workflow: workflow,
               source_node_id: start_node.node_id,
               target_node_id: loop_node.node_id)

        create(:ai_workflow_edge,
               ai_workflow: workflow,
               source_node_id: loop_node.node_id,
               target_node_id: process_node.node_id,
               edge_type: 'loop')

        # Loop back edge
        create(:ai_workflow_edge,
               ai_workflow: workflow,
               source_node_id: process_node.node_id,
               target_node_id: loop_node.node_id,
               edge_type: 'loop')

        # Exit condition edge
        create(:ai_workflow_edge,
               ai_workflow: workflow,
               source_node_id: loop_node.node_id,
               target_node_id: end_node.node_id,
               edge_type: 'conditional',
               is_conditional: true,
               condition: { expression: 'loop.iteration >= 5' })
      end
    end

    trait :with_variables do
      after(:create) do |workflow|
        create_list(:ai_workflow_variable, 3, ai_workflow: workflow)
      end
    end

    trait :with_schedule do
      after(:create) do |workflow|
        create(:ai_workflow_schedule, ai_workflow: workflow)
      end
    end

    trait :with_triggers do
      after(:create) do |workflow|
        create_list(:ai_workflow_trigger, 2, ai_workflow: workflow)
      end
    end

    trait :blog_generation do
      name { "Blog Content Generation" }
      description { "Automated blog post creation workflow with AI agents" }
      configuration do
        {
          execution_mode: 'sequential',
          max_execution_time: 1800,
          output_format: 'markdown',
          quality_checks: true
        }
      end
      metadata do
        {
          category: 'content_generation',
          use_case: 'blog_automation',
          complexity: 'medium',
          expected_duration: 600
        }
      end
    end

    trait :data_processing do
      name { "Data Processing Pipeline" }
      description { "ETL workflow for data transformation and analysis" }
      configuration do
        {
          execution_mode: 'parallel',
          max_execution_time: 7200,
          batch_size: 1000,
          data_validation: true
        }
      end
      metadata do
        {
          category: 'data_processing',
          use_case: 'etl_pipeline',
          complexity: 'high',
          expected_duration: 3600
        }
      end
    end

    trait :customer_support do
      name { "Customer Support Automation" }
      description { "Automated customer inquiry processing and response" }
      configuration do
        {
          execution_mode: 'conditional',
          max_execution_time: 900,
          escalation_rules: true,
          sentiment_analysis: true
        }
      end
    end

    trait :with_conditional_branch do
      after(:create) do |workflow|
        start_node = create(:ai_workflow_node, :start_node, ai_workflow: workflow)
        condition_node = create(:ai_workflow_node, :condition, ai_workflow: workflow)
        success_node = create(:ai_workflow_node, :ai_agent, ai_workflow: workflow, name: 'Success Handler')
        failure_node = create(:ai_workflow_node, :api_call, ai_workflow: workflow, name: 'Failure Handler')
        end_node = create(:ai_workflow_node, :end_node, ai_workflow: workflow)

        create(:ai_workflow_edge,
               ai_workflow: workflow,
               source_node_id: start_node.node_id,
               target_node_id: condition_node.node_id)

        create(:ai_workflow_edge,
               ai_workflow: workflow,
               source_node_id: condition_node.node_id,
               target_node_id: success_node.node_id,
               edge_type: 'conditional',
               is_conditional: true,
               condition: { expression: 'score >= threshold' })

        create(:ai_workflow_edge,
               ai_workflow: workflow,
               source_node_id: condition_node.node_id,
               target_node_id: failure_node.node_id,
               edge_type: 'conditional',
               is_conditional: true,
               condition: { expression: 'score < threshold' })

        create(:ai_workflow_edge,
               ai_workflow: workflow,
               source_node_id: success_node.node_id,
               target_node_id: end_node.node_id)

        create(:ai_workflow_edge,
               ai_workflow: workflow,
               source_node_id: failure_node.node_id,
               target_node_id: end_node.node_id)
      end
    end

    trait :with_execution_history do
      after(:create) do |workflow|
        create_list(:ai_workflow_run, 5, ai_workflow: workflow)
      end
    end

    trait :with_parallel_execution do
      configuration do
        {
          execution_mode: 'parallel',
          max_execution_time: 1800,
          max_parallel_nodes: 10,
          retry_policy: {
            max_retries: 2,
            retry_delay: 3,
            exponential_backoff: true
          },
          error_handling: {
            on_error: 'continue',
            notify_on_failure: false
          }
        }
      end

      after(:create) do |workflow|
        # Create parallel execution structure
        start_node = create(:ai_workflow_node, :start_node, ai_workflow: workflow)
        parallel_nodes = create_list(:ai_workflow_node, 3, :ai_agent, ai_workflow: workflow)
        merge_node = create(:ai_workflow_node, :merge, ai_workflow: workflow)
        end_node = create(:ai_workflow_node, :end_node, ai_workflow: workflow)

        # Connect start to all parallel nodes
        parallel_nodes.each do |node|
          create(:ai_workflow_edge,
                 ai_workflow: workflow,
                 source_node_id: start_node.node_id,
                 target_node_id: node.node_id)
        end

        # Connect all parallel nodes to merge node
        parallel_nodes.each do |node|
          create(:ai_workflow_edge,
                 ai_workflow: workflow,
                 source_node_id: node.node_id,
                 target_node_id: merge_node.node_id)
        end

        # Connect merge to end
        create(:ai_workflow_edge,
               ai_workflow: workflow,
               source_node_id: merge_node.node_id,
               target_node_id: end_node.node_id)
      end
    end
  end
end
