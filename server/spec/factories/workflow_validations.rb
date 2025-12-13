# frozen_string_literal: true

FactoryBot.define do
  factory :workflow_validation do
    association :workflow, factory: :ai_workflow
    overall_status { 'valid' }
    health_score { 100 }
    total_nodes { 5 }
    validated_nodes { 5 }
    issues { [] }
    validation_duration_ms { rand(100..1000) }

    trait :valid do
      overall_status { 'valid' }
      health_score { 100 }
      issues { [] }
    end

    trait :invalid do
      overall_status { 'invalid' }
      health_score { 45 }
      issues do
        [
          {
            code: 'missing_start_node',
            severity: 'error',
            category: 'structure',
            message: 'Workflow must have at least one start node',
            auto_fixable: false,
            affected_nodes: []
          },
          {
            code: 'circular_dependency',
            severity: 'error',
            category: 'structure',
            message: 'Workflow contains circular dependencies',
            auto_fixable: false,
            affected_nodes: [ 'node_1', 'node_2', 'node_3' ]
          }
        ]
      end
    end

    trait :with_warnings do
      overall_status { 'warning' }
      health_score { 75 }
      issues do
        [
          {
            code: 'orphaned_node',
            severity: 'warning',
            category: 'connectivity',
            message: 'Node is not connected to workflow',
            auto_fixable: true,
            affected_nodes: [ 'node_4' ]
          },
          {
            code: 'missing_description',
            severity: 'warning',
            category: 'configuration',
            message: 'Node is missing description',
            auto_fixable: false,
            affected_nodes: [ 'node_2' ]
          },
          {
            code: 'performance_concern',
            severity: 'info',
            category: 'performance',
            message: 'Node timeout may be too high',
            auto_fixable: false,
            affected_nodes: [ 'node_3' ]
          }
        ]
      end
    end

    trait :partial_validation do
      validated_nodes { 3 }
      total_nodes { 5 }
      health_score { 85 }
      issues do
        [
          {
            code: 'validation_incomplete',
            severity: 'info',
            category: 'structure',
            message: 'Not all nodes were validated',
            auto_fixable: false,
            affected_nodes: []
          }
        ]
      end
    end

    trait :auto_fixable_issues do
      overall_status { 'warning' }
      health_score { 80 }
      issues do
        [
          {
            code: 'missing_edge_labels',
            severity: 'warning',
            category: 'configuration',
            message: 'Some edges are missing labels',
            auto_fixable: true,
            fix_action: 'auto_generate_labels',
            affected_nodes: [ 'node_1', 'node_2' ]
          },
          {
            code: 'default_timeout',
            severity: 'info',
            category: 'configuration',
            message: 'Nodes using default timeout values',
            auto_fixable: true,
            fix_action: 'set_recommended_timeouts',
            affected_nodes: [ 'node_3', 'node_4' ]
          }
        ]
      end
    end

    trait :security_issues do
      overall_status { 'invalid' }
      health_score { 30 }
      issues do
        [
          {
            code: 'exposed_credentials',
            severity: 'error',
            category: 'security',
            message: 'API keys found in node configuration',
            auto_fixable: false,
            affected_nodes: [ 'node_2' ],
            recommendation: 'Move credentials to secure storage'
          },
          {
            code: 'unvalidated_input',
            severity: 'warning',
            category: 'security',
            message: 'Node accepts unvalidated user input',
            auto_fixable: false,
            affected_nodes: [ 'node_1' ],
            recommendation: 'Add input validation rules'
          }
        ]
      end
    end

    trait :performance_issues do
      overall_status { 'warning' }
      health_score { 65 }
      issues do
        [
          {
            code: 'high_timeout',
            severity: 'warning',
            category: 'performance',
            message: 'Node timeout exceeds recommended value',
            auto_fixable: true,
            affected_nodes: [ 'node_3' ],
            current_value: 600,
            recommended_value: 300
          },
          {
            code: 'sequential_bottleneck',
            severity: 'info',
            category: 'performance',
            message: 'Nodes could be parallelized for better performance',
            auto_fixable: false,
            affected_nodes: [ 'node_4', 'node_5' ]
          }
        ]
      end
    end

    trait :stale do
      created_at { 2.hours.ago }
      overall_status { 'warning' }
      health_score { 70 }
      issues do
        [
          {
            code: 'stale_validation',
            severity: 'info',
            category: 'structure',
            message: 'Validation results may be outdated',
            auto_fixable: false,
            affected_nodes: []
          }
        ]
      end
    end

    trait :healthy do
      overall_status { 'valid' }
      health_score { 95 }
      validated_nodes { total_nodes }
      issues do
        [
          {
            code: 'optimization_suggestion',
            severity: 'info',
            category: 'performance',
            message: 'Consider adding caching for improved performance',
            auto_fixable: false,
            affected_nodes: [ 'node_2' ]
          }
        ]
      end
    end

    trait :unhealthy do
      overall_status { 'invalid' }
      health_score { 40 }
      issues do
        [
          {
            code: 'missing_start_node',
            severity: 'error',
            category: 'structure',
            message: 'No start node defined',
            auto_fixable: false,
            affected_nodes: []
          },
          {
            code: 'unreachable_nodes',
            severity: 'error',
            category: 'connectivity',
            message: 'Some nodes cannot be reached from start',
            auto_fixable: false,
            affected_nodes: [ 'node_4', 'node_5' ]
          },
          {
            code: 'invalid_configuration',
            severity: 'error',
            category: 'configuration',
            message: 'Node configuration is invalid',
            auto_fixable: false,
            affected_nodes: [ 'node_3' ]
          }
        ]
      end
    end
  end
end
