# frozen_string_literal: true

FactoryBot.define do
  factory :ai_workflow_edge, class: "Ai::WorkflowEdge" do
    association :workflow, factory: :ai_workflow
    edge_id { SecureRandom.uuid }
    source_node_id { create(:ai_workflow_node, workflow: workflow).node_id }
    target_node_id { create(:ai_workflow_node, workflow: workflow).node_id }
    edge_type { 'default' }
    condition { {} }
    configuration do
      {
        label: 'Next',
        animated: false,
        style: {
          stroke: '#000000',
          strokeWidth: 2
        }
      }
    end

    trait :conditional do
      edge_type { 'conditional' }
      condition do
        {
          expression: 'output.status == "success"',
          operator: '==',
          value: 'success',
          data_type: 'string'
        }
      end
      configuration do
        {
          label: 'If Success',
          animated: true,
          style: {
            stroke: '#22c55e',
            strokeWidth: 2,
            strokeDasharray: '5,5'
          }
        }
      end
    end

    trait :error_path do
      edge_type { 'error' }
      condition do
        {
          expression: 'output.error != null',
          trigger_on_error: true
        }
      end
      configuration do
        {
          label: 'On Error',
          animated: false,
          style: {
            stroke: '#ef4444',
            strokeWidth: 2,
            markerEnd: 'error-arrow'
          }
        }
      end
    end

    # Loop body edge - from loop node's 'body' handle to processing node
    # Uses 'default' edge_type since routing is determined by handle, not type
    trait :loop_body do
      edge_type { 'default' }
      condition { {} }
      configuration do
        {
          label: 'Loop Body',
          animated: true,
          style: {
            stroke: '#3b82f6',
            strokeWidth: 2,
            strokeDasharray: '10,5'
          }
        }
      end
    end

    # Loop back edge - from processing node back to loop node's 'loop-back' handle
    # Uses 'loop' edge_type to indicate loop iteration
    trait :loop_back do
      edge_type { 'loop' }
      condition { {} }
      configuration do
        {
          label: 'Continue Loop',
          animated: true,
          style: {
            stroke: '#8b5cf6',
            strokeWidth: 2,
            markerEnd: 'loop-arrow'
          }
        }
      end
    end

    # Loop exit edge - from loop node's 'exit' handle to next node
    # Uses 'default' edge_type since routing is determined by handle
    trait :loop_exit do
      edge_type { 'default' }
      condition { {} }
      configuration do
        {
          label: 'Exit Loop',
          animated: false,
          style: {
            stroke: '#f59e0b',
            strokeWidth: 2
          }
        }
      end
    end

    # Parallel branch edge - for split node outputs
    # Uses 'default' edge_type since parallel execution is determined by node type
    trait :parallel_branch do
      edge_type { 'default' }
      condition { {} }
      configuration do
        {
          label: 'Parallel',
          animated: false,
          parallel_execution: true,
          style: {
            stroke: '#06b6d4',
            strokeWidth: 3
          }
        }
      end
    end

    # Merge input edge - for merge node inputs
    # Uses 'default' edge_type since merge behavior is determined by node
    trait :merge_input do
      edge_type { 'default' }
      condition { {} }
      configuration do
        {
          label: 'Merge',
          animated: false,
          wait_for_all: true,
          merge_strategy: 'combine_outputs',
          style: {
            stroke: '#10b981',
            strokeWidth: 2,
            markerEnd: 'merge-arrow'
          }
        }
      end
    end

    trait :timeout_edge do
      edge_type { 'timeout' }
      condition do
        {
          timeout_seconds: 300,
          trigger_on_timeout: true
        }
      end
      configuration do
        {
          label: 'Timeout',
          animated: false,
          style: {
            stroke: '#f97316',
            strokeWidth: 2,
            strokeDasharray: '15,5'
          }
        }
      end
    end

    # Approval granted edge - from human_approval node when approved
    # Uses 'success' edge_type to indicate successful approval
    trait :approval_granted do
      edge_type { 'success' }
      condition do
        {
          expression: 'approval.status == "approved"'
        }
      end
      configuration do
        {
          label: 'Approved',
          animated: false,
          style: {
            stroke: '#22c55e',
            strokeWidth: 2
          }
        }
      end
    end

    # Approval denied edge - from human_approval node when denied
    # Uses 'error' edge_type to indicate rejection path
    trait :approval_denied do
      edge_type { 'error' }
      condition do
        {
          expression: 'approval.status == "denied"'
        }
      end
      configuration do
        {
          label: 'Denied',
          animated: false,
          style: {
            stroke: '#ef4444',
            strokeWidth: 2
          }
        }
      end
    end

    trait :weighted do
      condition do
        {
          weight: 0.8,
          probability: 80
        }
      end
      configuration do
        {
          label: '80% likely',
          show_probability: true,
          style: {
            stroke: '#6366f1',
            strokeWidth: (rand * 3 + 1).round(1)
          }
        }
      end
    end

    # Data dependency edge - edge with required input data validation
    # Uses 'conditional' edge_type since it has validation conditions
    trait :data_dependency do
      edge_type { 'conditional' }
      condition do
        {
          expression: 'input.user_id != null && input.session_token != null',
          required_data: [ 'input.user_id', 'input.session_token' ]
        }
      end
      configuration do
        {
          label: 'Data Required',
          validate_input: true,
          style: {
            stroke: '#84cc16',
            strokeWidth: 2,
            strokeDasharray: '3,3'
          }
        }
      end
    end

    # High priority edge - uses default type with priority in configuration
    trait :priority_high do
      edge_type { 'default' }
      priority { 1 }
      condition { {} }
      configuration do
        {
          label: 'High Priority',
          priority: 'high',
          style: {
            stroke: '#dc2626',
            strokeWidth: 3
          }
        }
      end
    end

    # Low priority edge - uses default type with priority in configuration
    trait :priority_low do
      edge_type { 'default' }
      priority { 10 }
      condition { {} }
      configuration do
        {
          label: 'Low Priority',
          priority: 'low',
          style: {
            stroke: '#6b7280',
            strokeWidth: 1
          }
        }
      end
    end

    # Complex conditional expressions
    trait :complex_condition do
      edge_type { 'conditional' }
      condition do
        {
          expression: '(output.score > 0.8 && output.confidence > 0.9) || output.manual_override == true',
          variables: {
            'threshold_score': 0.8,
            'threshold_confidence': 0.9
          },
          operator: 'complex'
        }
      end
    end

    trait :api_success do
      edge_type { 'conditional' }
      condition do
        {
          expression: 'response.status >= 200 && response.status < 300',
          http_status_check: true
        }
      end
      configuration do
        {
          label: 'API Success',
          style: {
            stroke: '#22c55e',
            strokeWidth: 2
          }
        }
      end
    end

    trait :api_error do
      edge_type { 'error' }
      condition do
        {
          expression: 'response.status >= 400 || response.error != null',
          http_status_check: true,
          trigger_on_error: true
        }
      end
      configuration do
        {
          label: 'API Error',
          style: {
            stroke: '#ef4444',
            strokeWidth: 2
          }
        }
      end
    end

    # Factory with realistic workflow connections
    factory :blog_generation_edge, parent: :ai_workflow_edge do
      configuration do
        {
          label: 'Generate Content',
          description: 'Pass topic to content generator',
          data_mapping: {
            'topic': 'input.blog_topic',
            'style': 'input.writing_style'
          },
          style: {
            stroke: '#3b82f6',
            strokeWidth: 2
          }
        }
      end
    end

    factory :content_review_edge, parent: :ai_workflow_edge do
      configuration do
        {
          label: 'Review Content',
          description: 'Send generated content for review',
          data_mapping: {
            'content': 'previous.generated_content',
            'criteria': 'workflow.quality_criteria'
          },
          style: {
            stroke: '#f59e0b',
            strokeWidth: 2
          }
        }
      end
    end
  end
end
