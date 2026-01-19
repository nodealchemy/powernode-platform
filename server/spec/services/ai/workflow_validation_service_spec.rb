# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::WorkflowValidationService do
  let(:account) { create(:account) }
  let(:user) { create(:user, :owner, account: account) }
  let(:workflow) { create(:ai_workflow, account: account, creator: user) }
  let(:service) { described_class.new(workflow) }

  describe '#validate' do
    context 'with empty workflow' do
      it 'detects empty workflow as invalid' do
        result = service.validate

        expect(result[:overall_status]).to eq('invalid')
        expect(result[:total_nodes]).to eq(0)
        expect(result[:validated_nodes]).to eq(0)
        expect(result[:health_score]).to be < 100
        expect(result[:issues]).to include(
          hash_including(
            code: 'empty_workflow',
            severity: 'error',
            category: 'structural'
          )
        )
      end
    end

    context 'with structural validation' do
      context 'start node detection' do
        it 'detects missing start node' do
          create(:ai_workflow_node, :action, workflow: workflow)

          result = service.validate

          expect(result[:issues]).to include(
            hash_including(
              code: 'missing_start_node',
              severity: 'error',
              category: 'structural'
            )
          )
        end

        it 'detects multiple start nodes' do
          create(:ai_workflow_node, :trigger, workflow: workflow)
          node2 = create(:ai_workflow_node, :action, workflow: workflow)
          node2.update_column(:metadata, { 'is_start' => true })

          result = service.validate

          expect(result[:issues]).to include(
            hash_including(
              code: 'multiple_start_nodes',
              severity: 'error',
              category: 'structural'
            )
          )
        end

        it 'accepts workflow with single trigger as start' do
          create(:ai_workflow_node, :trigger, workflow: workflow)
          create(:ai_workflow_node, :action, workflow: workflow)

          result = service.validate

          start_issues = result[:issues].select { |i| i[:code] =~ /start/ }
          expect(start_issues).to be_empty
        end
      end

      context 'end node detection' do
        it 'warns about missing end node' do
          trigger = create(:ai_workflow_node, :trigger, workflow: workflow)
          action = create(:ai_workflow_node, :action, workflow: workflow)
          create(:ai_workflow_edge, workflow: workflow, source_node: trigger, target_node: action)

          result = service.validate

          expect(result[:issues]).to include(
            hash_including(
              code: 'missing_end_node',
              severity: 'warning',
              category: 'structural'
            )
          )
        end

        it 'accepts workflow with explicit end node' do
          trigger = create(:ai_workflow_node, :trigger, workflow: workflow)
          end_node = create(:ai_workflow_node, node_type: 'end', workflow: workflow)
          create(:ai_workflow_edge, workflow: workflow, source_node: trigger, target_node: end_node)

          result = service.validate

          end_issues = result[:issues].select { |i| i[:code] == 'missing_end_node' }
          expect(end_issues).to be_empty
        end
      end
    end

    context 'with connectivity validation' do
      context 'orphaned nodes' do
        it 'detects orphaned action nodes' do
          create(:ai_workflow_node, :trigger, workflow: workflow)
          orphaned = create(:ai_workflow_node, :action, workflow: workflow)

          result = service.validate

          expect(result[:issues]).to include(
            hash_including(
              code: 'orphaned_node',
              severity: 'warning',
              category: 'connectivity',
              node_id: orphaned.id,
              auto_fixable: true
            )
          )
        end

        it 'does not flag trigger as orphaned' do
          create(:ai_workflow_node, :trigger, workflow: workflow)

          result = service.validate

          orphaned_issues = result[:issues].select { |i| i[:code] == 'orphaned_node' }
          expect(orphaned_issues).to be_empty
        end

        it 'does not flag connected nodes as orphaned' do
          trigger = create(:ai_workflow_node, :trigger, workflow: workflow)
          action = create(:ai_workflow_node, :action, workflow: workflow)
          create(:ai_workflow_edge, workflow: workflow, source_node: trigger, target_node: action)

          result = service.validate

          orphaned_issues = result[:issues].select { |i| i[:code] == 'orphaned_node' }
          expect(orphaned_issues).to be_empty
        end
      end

      context 'dead-end nodes' do
        it 'detects action nodes with no output' do
          trigger = create(:ai_workflow_node, :trigger, workflow: workflow)
          dead_end = create(:ai_workflow_node, :action, workflow: workflow)
          create(:ai_workflow_edge, workflow: workflow, source_node: trigger, target_node: dead_end)

          result = service.validate

          expect(result[:issues]).to include(
            hash_including(
              code: 'dead_end_node',
              severity: 'info',
              category: 'connectivity',
              node_id: dead_end.id
            )
          )
        end

        it 'does not flag end nodes as dead-end' do
          trigger = create(:ai_workflow_node, :trigger, workflow: workflow)
          end_node = create(:ai_workflow_node, node_type: 'end', workflow: workflow)
          create(:ai_workflow_edge, workflow: workflow, source_node: trigger, target_node: end_node)

          result = service.validate

          dead_end_issues = result[:issues].select { |i| i[:code] == 'dead_end_node' }
          expect(dead_end_issues).to be_empty
        end
      end

      context 'trigger validation' do
        it 'detects trigger with no output as error' do
          create(:ai_workflow_node, :trigger, workflow: workflow)

          result = service.validate

          expect(result[:overall_status]).to eq('invalid')
          expect(result[:issues]).to include(
            hash_including(
              code: 'trigger_no_output',
              severity: 'error',
              category: 'connectivity'
            )
          )
        end

        it 'accepts trigger with valid output connection' do
          trigger = create(:ai_workflow_node, :trigger, workflow: workflow)
          action = create(:ai_workflow_node, :action, workflow: workflow)
          create(:ai_workflow_edge, workflow: workflow, source_node: trigger, target_node: action)

          result = service.validate

          trigger_issues = result[:issues].select { |i| i[:code] == 'trigger_no_output' }
          expect(trigger_issues).to be_empty
        end
      end
    end

    context 'with node configuration validation' do
      context 'ai_agent nodes' do
        it 'detects missing agent_id' do
          trigger = create(:ai_workflow_node, :trigger, workflow: workflow)
          # Build node without configuration to avoid factory's after(:build) callback setting agent_id
          agent_node = Ai::WorkflowNode.new(
            workflow: workflow,
            node_id: SecureRandom.uuid,
            name: 'Test Agent Node',
            node_type: 'ai_agent',
            position: { x: 100, y: 100 },
            configuration: { prompt: 'Test' }
          )
          agent_node.save(validate: false)
          create(:ai_workflow_edge, workflow: workflow, source_node: trigger, target_node: agent_node)

          result = service.validate

          expect(result[:issues]).to include(
            hash_including(
              code: 'missing_agent',
              severity: 'error',
              category: 'configuration',
              node_id: agent_node.id
            )
          )
        end

        it 'detects missing prompt' do
          trigger = create(:ai_workflow_node, :trigger, workflow: workflow)
          agent_node = create(
            :ai_workflow_node,
            node_type: 'ai_agent',
            workflow: workflow,
            configuration: { agent_id: '123' }
          )
          create(:ai_workflow_edge, workflow: workflow, source_node: trigger, target_node: agent_node)

          result = service.validate

          expect(result[:issues]).to include(
            hash_including(
              code: 'missing_prompt',
              severity: 'error',
              category: 'configuration',
              node_id: agent_node.id
            )
          )
        end

        it 'warns about missing timeout' do
          trigger = create(:ai_workflow_node, :trigger, workflow: workflow)
          agent_node = create(
            :ai_workflow_node,
            node_type: 'ai_agent',
            workflow: workflow,
            configuration: { agent_id: '123', prompt: 'Test' }
          )
          create(:ai_workflow_edge, workflow: workflow, source_node: trigger, target_node: agent_node)

          result = service.validate

          expect(result[:issues]).to include(
            hash_including(
              code: 'missing_timeout',
              severity: 'warning',
              category: 'configuration',
              node_id: agent_node.id,
              auto_fixable: true
            )
          )
        end

        it 'accepts valid ai_agent configuration' do
          trigger = create(:ai_workflow_node, :trigger, workflow: workflow)
          agent_node = create(
            :ai_workflow_node,
            node_type: 'ai_agent',
            workflow: workflow,
            configuration: { agent_id: '123', prompt: 'Test', timeout_seconds: 120 }
          )
          create(:ai_workflow_edge, workflow: workflow, source_node: trigger, target_node: agent_node)

          result = service.validate

          # Should not have any configuration errors for this node
          config_issues = result[:issues].select { |i| i[:node_id] == agent_node.id && i[:category] == 'configuration' }
          expect(config_issues).to be_empty
        end
      end

      context 'api_call nodes' do
        it 'detects missing URL' do
          trigger = create(:ai_workflow_node, :trigger, workflow: workflow)
          api_node = build(
            :ai_workflow_node,
            node_type: 'api_call',
            workflow: workflow,
            configuration: { method: 'GET' }
          )
          api_node.save(validate: false)
          create(:ai_workflow_edge, workflow: workflow, source_node: trigger, target_node: api_node)

          result = service.validate

          expect(result[:issues]).to include(
            hash_including(
              code: 'missing_url',
              severity: 'error',
              category: 'configuration',
              node_id: api_node.id
            )
          )
        end

        it 'detects missing HTTP method' do
          trigger = create(:ai_workflow_node, :trigger, workflow: workflow)
          api_node = build(
            :ai_workflow_node,
            node_type: 'api_call',
            workflow: workflow,
            configuration: { url: 'https://example.com' }
          )
          api_node.save(validate: false)
          create(:ai_workflow_edge, workflow: workflow, source_node: trigger, target_node: api_node)

          result = service.validate

          expect(result[:issues]).to include(
            hash_including(
              code: 'missing_method',
              severity: 'error',
              category: 'configuration',
              node_id: api_node.id
            )
          )
        end

        it 'accepts valid api_call configuration' do
          trigger = create(:ai_workflow_node, :trigger, workflow: workflow)
          api_node = create(
            :ai_workflow_node,
            node_type: 'api_call',
            workflow: workflow,
            configuration: { url: 'https://example.com', method: 'GET' }
          )
          create(:ai_workflow_edge, workflow: workflow, source_node: trigger, target_node: api_node)

          result = service.validate

          # Should not have any configuration errors for this node
          config_issues = result[:issues].select { |i| i[:node_id] == api_node.id && i[:category] == 'configuration' }
          expect(config_issues).to be_empty
        end
      end

      context 'condition nodes' do
        it 'detects missing conditions array' do
          trigger = create(:ai_workflow_node, :trigger, workflow: workflow)
          condition_node = build(
            :ai_workflow_node,
            node_type: 'condition',
            workflow: workflow,
            configuration: {}
          )
          condition_node.save(validate: false)
          create(:ai_workflow_edge, workflow: workflow, source_node: trigger, target_node: condition_node)

          result = service.validate

          expect(result[:issues]).to include(
            hash_including(
              code: 'missing_conditions',
              severity: 'error',
              category: 'configuration',
              node_id: condition_node.id
            )
          )
        end

        it 'accepts valid condition configuration' do
          trigger = create(:ai_workflow_node, :trigger, workflow: workflow)
          condition_node = create(
            :ai_workflow_node,
            node_type: 'condition',
            workflow: workflow,
            configuration: {
              conditions: [
                { field: 'status', operator: 'equals', value: 'active' }
              ]
            }
          )
          create(:ai_workflow_edge, workflow: workflow, source_node: trigger, target_node: condition_node)

          result = service.validate

          # Should not have any configuration errors for this node
          config_issues = result[:issues].select { |i| i[:node_id] == condition_node.id && i[:category] == 'configuration' }
          expect(config_issues).to be_empty
        end
      end

      context 'loop nodes' do
        it 'detects missing iteration source' do
          trigger = create(:ai_workflow_node, :trigger, workflow: workflow)
          loop_node = build(
            :ai_workflow_node,
            node_type: 'loop',
            workflow: workflow,
            configuration: {}
          )
          loop_node.save(validate: false)
          create(:ai_workflow_edge, workflow: workflow, source_node: trigger, target_node: loop_node)

          result = service.validate

          expect(result[:issues]).to include(
            hash_including(
              code: 'missing_iteration_source',
              severity: 'error',
              category: 'configuration',
              node_id: loop_node.id
            )
          )
        end

        it 'warns about missing max_iterations' do
          trigger = create(:ai_workflow_node, :trigger, workflow: workflow)
          loop_node = create(
            :ai_workflow_node,
            node_type: 'loop',
            workflow: workflow,
            configuration: { iteration_source: 'items' }
          )
          create(:ai_workflow_edge, workflow: workflow, source_node: trigger, target_node: loop_node)

          result = service.validate

          expect(result[:issues]).to include(
            hash_including(
              code: 'missing_max_iterations',
              severity: 'warning',
              category: 'configuration',
              node_id: loop_node.id,
              auto_fixable: true
            )
          )
        end
      end

      context 'human_approval nodes' do
        it 'detects missing approvers' do
          trigger = create(:ai_workflow_node, :trigger, workflow: workflow)
          # Create node with validate: false to bypass model validation
          approval_node = build(
            :ai_workflow_node,
            node_type: 'human_approval',
            workflow: workflow,
            configuration: {}
          )
          approval_node.save(validate: false)
          create(:ai_workflow_edge, workflow: workflow, source_node: trigger, target_node: approval_node)

          result = service.validate

          expect(result[:issues]).to include(
            hash_including(
              code: 'missing_approvers',
              severity: 'error',
              category: 'configuration',
              node_id: approval_node.id
            )
          )
        end

        it 'accepts valid human_approval configuration' do
          trigger = create(:ai_workflow_node, :trigger, workflow: workflow)
          approval_node = create(
            :ai_workflow_node,
            node_type: 'human_approval',
            workflow: workflow,
            configuration: { approvers: [ 'user1@example.com' ] }
          )
          create(:ai_workflow_edge, workflow: workflow, source_node: trigger, target_node: approval_node)

          result = service.validate

          # Should not have any configuration errors for this node
          config_issues = result[:issues].select { |i| i[:node_id] == approval_node.id && i[:category] == 'configuration' }
          expect(config_issues).to be_empty
        end
      end
    end

    context 'with complex workflow structures' do
      it 'validates branching workflow with conditions' do
        trigger = create(:ai_workflow_node, :trigger, workflow: workflow)
        condition = create(
          :ai_workflow_node,
          node_type: 'condition',
          workflow: workflow,
          configuration: { conditions: [ { field: 'status', operator: 'equals', value: 'active' } ] }
        )
        action1 = create(:ai_workflow_node, :action, workflow: workflow)
        action2 = create(:ai_workflow_node, :action, workflow: workflow)

        create(:ai_workflow_edge, workflow: workflow, source_node: trigger, target_node: condition)
        create(:ai_workflow_edge, workflow: workflow, source_node: condition, target_node: action1)
        create(:ai_workflow_edge, workflow: workflow, source_node: condition, target_node: action2)

        result = service.validate

        expect(result[:total_nodes]).to eq(4)
        expect(result[:validated_nodes]).to eq(4)
      end

      it 'validates sequential workflow chain' do
        trigger = create(:ai_workflow_node, :trigger, workflow: workflow)
        action1 = create(:ai_workflow_node, :action, workflow: workflow)
        action2 = create(:ai_workflow_node, :action, workflow: workflow)
        action3 = create(:ai_workflow_node, :action, workflow: workflow)

        create(:ai_workflow_edge, workflow: workflow, source_node: trigger, target_node: action1)
        create(:ai_workflow_edge, workflow: workflow, source_node: action1, target_node: action2)
        create(:ai_workflow_edge, workflow: workflow, source_node: action2, target_node: action3)

        result = service.validate

        expect(result[:total_nodes]).to eq(4)
        expect(result[:validated_nodes]).to eq(4)
        # Only the last action should be dead-end
        dead_end_issues = result[:issues].select { |i| i[:code] == 'dead_end_node' }
        expect(dead_end_issues.length).to eq(1)
      end
    end

    context 'health score calculation' do
      it 'returns perfect score for valid workflow' do
        trigger = create(:ai_workflow_node, :trigger, workflow: workflow)
        action = create(
          :ai_workflow_node,
          node_type: 'api_call',
          workflow: workflow,
          configuration: { url: 'https://example.com', method: 'GET' }
        )
        end_node = create(:ai_workflow_node, node_type: 'end', workflow: workflow)

        create(:ai_workflow_edge, workflow: workflow, source_node: trigger, target_node: action)
        create(:ai_workflow_edge, workflow: workflow, source_node: action, target_node: end_node)

        result = service.validate

        expect(result[:health_score]).to eq(100)
        expect(result[:overall_status]).to eq('valid')
      end

      it 'deducts points for errors' do
        # Empty workflow = 1 error = -15 points
        result = service.validate

        expect(result[:health_score]).to eq(85)
        expect(result[:overall_status]).to eq('invalid')
      end

      it 'deducts points for warnings' do
        trigger = create(:ai_workflow_node, :trigger, workflow: workflow)
        action = create(:ai_workflow_node, :action, workflow: workflow)
        create(:ai_workflow_edge, workflow: workflow, source_node: trigger, target_node: action)

        result = service.validate

        # Missing end node = warning (-5 points)
        expect(result[:health_score]).to be >= 90
        expect(result[:overall_status]).to eq('warning')
      end

      it 'ensures health score never goes below 0' do
        # Create many errors
        10.times do
          create(:ai_workflow_node, :action, workflow: workflow)
        end

        result = service.validate

        expect(result[:health_score]).to be >= 0
        expect(result[:health_score]).to be <= 100
      end
    end

    context 'validation metadata' do
      it 'includes validation duration' do
        result = service.validate

        expect(result).to have_key(:validation_duration_ms)
        expect(result[:validation_duration_ms]).to be_a(Integer)
        expect(result[:validation_duration_ms]).to be > 0
      end

      it 'includes node counts' do
        3.times { create(:ai_workflow_node, :action, workflow: workflow) }

        result = service.validate

        expect(result[:total_nodes]).to eq(3)
        expect(result[:validated_nodes]).to eq(3)
      end

      it 'categorizes issues properly' do
        create(:ai_workflow_node, :trigger, workflow: workflow)
        orphaned = create(:ai_workflow_node, :action, workflow: workflow)

        result = service.validate

        expect(result[:issues]).to all(
          include(
            :code, :severity, :category, :message
          )
        )
      end
    end
  end
end
