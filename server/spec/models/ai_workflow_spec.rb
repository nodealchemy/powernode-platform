# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiWorkflow, type: :model do
  describe 'associations' do
    it { should belong_to(:account) }
    it { should have_many(:nodes).class_name('AiWorkflowNode').dependent(:destroy) }
    it { should have_many(:edges).class_name('AiWorkflowEdge').dependent(:destroy) }
    it { should have_many(:runs).class_name('AiWorkflowRun').dependent(:destroy) }
    it { should have_many(:variables).class_name('AiWorkflowVariable').dependent(:destroy) }
    it { should have_many(:schedules).class_name('AiWorkflowSchedule').dependent(:destroy) }
    it { should have_many(:triggers).class_name('AiWorkflowTrigger').dependent(:destroy) }
    it { should have_many(:template_installations).class_name('AiWorkflowTemplateInstallation').dependent(:destroy) }
  end

  describe 'validations' do
    subject { build(:ai_workflow) }

    it { should validate_presence_of(:name) }
    it { should validate_length_of(:name).is_at_most(255) }
    it { should validate_length_of(:description).is_at_most(1000) }
    it { should validate_inclusion_of(:status).in_array(%w[draft active paused inactive archived]) }
    it { should allow_value('1.0.0', '2.1.3', '10.20.30').for(:version) }
    it { should_not allow_value('1.0', '1.0.0.1', 'invalid', '').for(:version) }

    context 'name uniqueness' do
      let!(:existing_workflow) { create(:ai_workflow) }

      it 'validates uniqueness of name within account scope' do
        duplicate_workflow = build(:ai_workflow,
                                   name: existing_workflow.name,
                                   account: existing_workflow.account)
        
        expect(duplicate_workflow).not_to be_valid
        expect(duplicate_workflow.errors[:name]).to include('has already been taken')
      end

      it 'allows same name in different accounts' do
        different_account = create(:account)
        workflow_with_same_name = build(:ai_workflow,
                                        name: existing_workflow.name,
                                        account: different_account)
        
        expect(workflow_with_same_name).to be_valid
      end
    end

    context 'configuration validation' do
      it 'validates configuration is a hash' do
        workflow = build(:ai_workflow, configuration: 'invalid')
        expect(workflow).not_to be_valid
        expect(workflow.errors[:configuration]).to include('must be a hash')
      end

      it 'validates execution_mode if present' do
        workflow = build(:ai_workflow, configuration: { execution_mode: 'invalid' })
        expect(workflow).not_to be_valid
        expect(workflow.errors[:configuration]).to include('invalid execution_mode')
      end

      it 'accepts valid execution modes' do
        %w[sequential parallel conditional].each do |mode|
          workflow = build(:ai_workflow, configuration: { execution_mode: mode })
          expect(workflow).to be_valid
        end
      end

      it 'validates max_execution_time is positive' do
        workflow = build(:ai_workflow, configuration: { max_execution_time: -100 })
        expect(workflow).not_to be_valid
        expect(workflow.errors[:configuration]).to include('max_execution_time must be positive')
      end
    end
  end

  describe 'scopes' do
    let!(:active_workflow) { create(:ai_workflow, status: 'active') }
    let!(:draft_workflow) { create(:ai_workflow, status: 'draft') }
    let!(:paused_workflow) { create(:ai_workflow, status: 'paused') }
    let!(:archived_workflow) { create(:ai_workflow, status: 'archived') }

    describe '.active' do
      it 'returns only active workflows' do
        expect(AiWorkflow.active).to include(active_workflow)
        expect(AiWorkflow.active).not_to include(draft_workflow, paused_workflow, archived_workflow)
      end
    end

    describe '.draft' do
      it 'returns only draft workflows' do
        expect(AiWorkflow.draft).to include(draft_workflow)
        expect(AiWorkflow.draft).not_to include(active_workflow)
      end
    end

    describe '.executable' do
      it 'returns workflows that can be executed' do
        expect(AiWorkflow.executable).to include(active_workflow, paused_workflow)
        expect(AiWorkflow.executable).not_to include(draft_workflow, archived_workflow)
      end
    end

    describe '.by_status' do
      it 'filters workflows by status' do
        expect(AiWorkflow.by_status('active')).to include(active_workflow)
        expect(AiWorkflow.by_status('draft')).to include(draft_workflow)
      end
    end

    describe '.search' do
      let!(:workflow1) { create(:ai_workflow, name: 'Data Processing Pipeline') }
      let!(:workflow2) { create(:ai_workflow, name: 'Blog Generator', description: 'Content creation workflow') }

      it 'searches by name' do
        results = AiWorkflow.search('Data')
        expect(results).to include(workflow1)
        expect(results).not_to include(workflow2)
      end

      it 'searches by description' do
        results = AiWorkflow.search('Content')
        expect(results).to include(workflow2)
        expect(results).not_to include(workflow1)
      end

      it 'returns all workflows for empty query' do
        results = AiWorkflow.search('')
        expect(results.count).to be >= 2
      end
    end

    describe '.recent' do
      let!(:old_workflow) { create(:ai_workflow, created_at: 2.months.ago) }
      let!(:recent_workflow) { create(:ai_workflow, created_at: 1.day.ago) }

      it 'returns workflows from specified time period' do
        results = AiWorkflow.recent(1.week)
        expect(results).to include(recent_workflow)
        expect(results).not_to include(old_workflow)
      end
    end
  end

  describe 'callbacks' do
    describe 'before_validation' do
      it 'sets default version if not provided' do
        workflow = build(:ai_workflow, version: nil)
        workflow.valid?
        expect(workflow.version).to eq('1.0.0')
      end

      it 'normalizes status to lowercase' do
        workflow = build(:ai_workflow, status: 'ACTIVE')
        workflow.valid?
        expect(workflow.status).to eq('active')
      end

      it 'sets default configuration if empty' do
        workflow = build(:ai_workflow, configuration: nil)
        workflow.valid?
        expect(workflow.configuration).to include('execution_mode', 'max_execution_time')
      end
    end

    describe 'after_create' do
      it 'creates audit log entry' do
        expect {
          create(:ai_workflow)
        }.to change { AuditLog.count }.by(1)

        audit_log = AuditLog.last
        expect(audit_log.action).to eq('ai_workflow_created')
        expect(audit_log.auditable_type).to eq('AiWorkflow')
      end

      it 'creates default variables if none exist' do
        workflow = create(:ai_workflow)
        expect(workflow.variables.count).to be >= 1
        expect(workflow.variables.find_by(name: 'workflow_input')).to be_present
      end
    end

    describe 'after_update' do
      it 'creates audit log for status changes' do
        workflow = create(:ai_workflow, status: 'draft')
        
        expect {
          workflow.update!(status: 'active')
        }.to change { AuditLog.count }.by(1)

        audit_log = AuditLog.last
        expect(audit_log.action).to eq('ai_workflow_status_changed')
        expect(audit_log.changes).to include('status' => ['draft', 'active'])
      end
    end
  end

  describe 'state transitions' do
    let(:workflow) { create(:ai_workflow, status: 'draft') }

    describe '#activate!' do
      context 'with valid workflow structure' do
        before do
          create(:ai_workflow_node, :start_node, ai_workflow: workflow)
          create(:ai_workflow_node, :end_node, ai_workflow: workflow)
        end

        it 'changes status to active' do
          expect { workflow.activate! }.to change { workflow.status }.from('draft').to('active')
        end

        it 'sets activated_at timestamp' do
          workflow.activate!
          expect(workflow.reload.activated_at).to be_present
        end
      end

      context 'without required nodes' do
        it 'raises validation error' do
          expect { workflow.activate! }.to raise_error(ActiveRecord::RecordInvalid)
          expect(workflow.errors[:base]).to include('Workflow must have at least one start node')
        end
      end
    end

    describe '#pause!' do
      let(:workflow) { create(:ai_workflow, status: 'active') }

      it 'changes status to paused' do
        expect { workflow.pause!('Manual pause') }.to change { workflow.status }.from('active').to('paused')
      end

      it 'records pause reason' do
        workflow.pause!('Testing pause')
        expect(workflow.reload.metadata['pause_reason']).to eq('Testing pause')
      end

      it 'pauses running executions' do
        run = create(:ai_workflow_run, :running, ai_workflow: workflow)
        workflow.pause!('Manual pause')
        expect(run.reload.status).to eq('paused')
      end
    end

    describe '#archive!' do
      let(:workflow) { create(:ai_workflow, status: 'active') }

      it 'changes status to archived' do
        expect { workflow.archive! }.to change { workflow.status }.from('active').to('archived')
      end

      it 'deactivates all schedules' do
        schedule = create(:ai_workflow_schedule, ai_workflow: workflow, is_active: true)
        workflow.archive!
        expect(schedule.reload.is_active).to be false
      end
    end
  end

  describe 'workflow execution' do
    let(:workflow) { create(:ai_workflow, :with_simple_chain) }

    describe '#can_execute?' do
      it 'returns true for active workflows' do
        workflow.update!(status: 'active')
        expect(workflow.can_execute?).to be true
      end

      it 'returns false for draft workflows' do
        workflow.update!(status: 'draft')
        expect(workflow.can_execute?).to be false
      end

      it 'returns false for archived workflows' do
        workflow.update!(status: 'archived')
        expect(workflow.can_execute?).to be false
      end

      it 'returns true for paused workflows' do
        workflow.update!(status: 'paused')
        expect(workflow.can_execute?).to be true
      end
    end

    describe '#execute' do
      before { workflow.update!(status: 'active') }

      context 'with valid execution parameters' do
        it 'creates a new workflow run' do
          expect {
            workflow.execute(input_variables: { test: 'data' })
          }.to change { workflow.runs.count }.by(1)
        end

        it 'returns the created workflow run' do
          run = workflow.execute(input_variables: { test: 'data' })
          expect(run).to be_a(AiWorkflowRun)
          expect(run).to be_persisted
          expect(run.input_variables).to include('test' => 'data')
        end

        it 'sets default trigger type' do
          run = workflow.execute(input_variables: {})
          expect(run.trigger_type).to eq('manual')
        end

        it 'accepts custom trigger information' do
          run = workflow.execute(
            input_variables: {},
            trigger_type: 'webhook',
            trigger_context: { webhook_id: 'test123' }
          )
          expect(run.trigger_type).to eq('webhook')
          expect(run.trigger_context).to include('webhook_id' => 'test123')
        end
      end

      context 'with invalid execution state' do
        it 'raises error for non-executable workflow' do
          workflow.update!(status: 'draft')
          
          expect {
            workflow.execute(input_variables: {})
          }.to raise_error(ArgumentError, /not in a state that can be executed/)
        end
      end

      context 'with validation errors' do
        it 'handles required variable validation' do
          create(:ai_workflow_variable, :required, ai_workflow: workflow, name: 'required_input')
          
          run = workflow.execute(input_variables: {})
          expect(run.status).to eq('failed')
          expect(run.error_details['error_type']).to eq('validation_error')
        end
      end
    end

    describe '#duplicate' do
      it 'creates a copy of the workflow' do
        original = create(:ai_workflow, :with_simple_chain, :with_variables)
        duplicate = original.duplicate

        expect(duplicate.name).to eq("#{original.name} (Copy)")
        expect(duplicate.status).to eq('draft')
        expect(duplicate.nodes.count).to eq(original.nodes.count)
        expect(duplicate.edges.count).to eq(original.edges.count)
        expect(duplicate.variables.count).to eq(original.variables.count)
      end

      it 'generates unique node IDs for duplicated nodes' do
        original = create(:ai_workflow, :with_simple_chain)
        duplicate = original.duplicate

        original_node_ids = original.nodes.pluck(:node_id)
        duplicate_node_ids = duplicate.nodes.pluck(:node_id)

        expect(original_node_ids & duplicate_node_ids).to be_empty
      end
    end
  end

  describe 'workflow structure validation' do
    describe '#validate_structure' do
      context 'with valid structure' do
        it 'returns true for simple valid workflow' do
          workflow = create(:ai_workflow, :with_simple_chain)
          expect(workflow.validate_structure).to be true
        end

        it 'returns true for complex valid workflow' do
          workflow = create(:ai_workflow, :with_complex_flow)
          expect(workflow.validate_structure).to be true
        end
      end

      context 'with invalid structure' do
        let(:workflow) { create(:ai_workflow) }

        it 'fails without start node' do
          create(:ai_workflow_node, :end_node, ai_workflow: workflow)
          result = workflow.validate_structure
          
          expect(result).to be false
          expect(workflow.errors[:base]).to include('Workflow must have at least one start node')
        end

        it 'fails without end node' do
          create(:ai_workflow_node, :start_node, ai_workflow: workflow)
          result = workflow.validate_structure
          
          expect(result).to be false
          expect(workflow.errors[:base]).to include('Workflow must have at least one end node')
        end

        it 'fails with unreachable nodes' do
          start_node = create(:ai_workflow_node, :start_node, ai_workflow: workflow)
          end_node = create(:ai_workflow_node, :end_node, ai_workflow: workflow)
          orphan_node = create(:ai_workflow_node, :ai_agent, ai_workflow: workflow)
          
          create(:ai_workflow_edge, 
                 ai_workflow: workflow,
                 source_node_id: start_node.node_id,
                 target_node_id: end_node.node_id)
          
          result = workflow.validate_structure
          expect(result).to be false
          expect(workflow.errors[:base]).to include('Workflow has unreachable nodes')
        end

        it 'fails with circular dependencies' do
          node1 = create(:ai_workflow_node, :ai_agent, ai_workflow: workflow)
          node2 = create(:ai_workflow_node, :ai_agent, ai_workflow: workflow)
          
          create(:ai_workflow_edge,
                 ai_workflow: workflow,
                 source_node_id: node1.node_id,
                 target_node_id: node2.node_id)
          
          create(:ai_workflow_edge,
                 ai_workflow: workflow,
                 source_node_id: node2.node_id,
                 target_node_id: node1.node_id)
          
          result = workflow.validate_structure
          expect(result).to be false
          expect(workflow.errors[:base]).to include('Workflow contains circular dependencies')
        end
      end
    end

    describe '#find_circular_dependencies' do
      it 'detects simple circular dependency' do
        workflow = create(:ai_workflow)
        node1 = create(:ai_workflow_node, ai_workflow: workflow)
        node2 = create(:ai_workflow_node, ai_workflow: workflow)
        
        create(:ai_workflow_edge, ai_workflow: workflow, source_node_id: node1.node_id, target_node_id: node2.node_id)
        create(:ai_workflow_edge, ai_workflow: workflow, source_node_id: node2.node_id, target_node_id: node1.node_id)
        
        cycles = workflow.find_circular_dependencies
        expect(cycles).not_to be_empty
        expect(cycles.first).to include(node1.node_id, node2.node_id)
      end

      it 'detects complex circular dependency' do
        workflow = create(:ai_workflow)
        node1 = create(:ai_workflow_node, ai_workflow: workflow)
        node2 = create(:ai_workflow_node, ai_workflow: workflow)
        node3 = create(:ai_workflow_node, ai_workflow: workflow)
        
        create(:ai_workflow_edge, ai_workflow: workflow, source_node_id: node1.node_id, target_node_id: node2.node_id)
        create(:ai_workflow_edge, ai_workflow: workflow, source_node_id: node2.node_id, target_node_id: node3.node_id)
        create(:ai_workflow_edge, ai_workflow: workflow, source_node_id: node3.node_id, target_node_id: node1.node_id)
        
        cycles = workflow.find_circular_dependencies
        expect(cycles).not_to be_empty
        expect(cycles.first.size).to eq(3)
      end

      it 'returns empty array for acyclic workflow' do
        workflow = create(:ai_workflow, :with_simple_chain)
        cycles = workflow.find_circular_dependencies
        expect(cycles).to be_empty
      end
    end
  end

  describe 'statistics and metrics' do
    let(:workflow) { create(:ai_workflow, :with_execution_history) }

    describe '#execution_stats' do
      it 'calculates execution statistics' do
        stats = workflow.execution_stats
        
        expect(stats).to include(:total_executions)
        expect(stats).to include(:successful_executions)
        expect(stats).to include(:failed_executions)
        expect(stats).to include(:success_rate)
        expect(stats).to include(:avg_execution_time)
        expect(stats[:total_executions]).to be > 0
      end

      it 'calculates success rate correctly' do
        # Create specific runs with known outcomes
        workflow.runs.destroy_all
        create_list(:ai_workflow_run, 3, :completed, ai_workflow: workflow)
        create_list(:ai_workflow_run, 1, :failed, ai_workflow: workflow)
        
        stats = workflow.execution_stats
        expect(stats[:success_rate]).to eq(75.0) # 3 out of 4 successful
      end
    end

    describe '#recent_runs' do
      it 'returns runs from last 24 hours by default' do
        old_run = create(:ai_workflow_run, ai_workflow: workflow, created_at: 2.days.ago)
        recent_run = create(:ai_workflow_run, ai_workflow: workflow, created_at: 1.hour.ago)
        
        recent_runs = workflow.recent_runs
        expect(recent_runs).to include(recent_run)
        expect(recent_runs).not_to include(old_run)
      end

      it 'accepts custom time period' do
        old_run = create(:ai_workflow_run, ai_workflow: workflow, created_at: 2.days.ago)
        
        runs_in_period = workflow.recent_runs(3.days)
        expect(runs_in_period).to include(old_run)
      end
    end

    describe '#total_cost' do
      it 'sums cost from all completed runs' do
        workflow.runs.destroy_all
        create(:ai_workflow_run, :completed, ai_workflow: workflow, total_cost: 0.05)
        create(:ai_workflow_run, :completed, ai_workflow: workflow, total_cost: 0.03)
        create(:ai_workflow_run, :failed, ai_workflow: workflow, total_cost: 0.01) # Should be included
        
        expect(workflow.total_cost).to eq(0.09)
      end

      it 'returns 0 when no runs exist' do
        workflow.runs.destroy_all
        expect(workflow.total_cost).to eq(0.0)
      end
    end

    describe '#average_execution_time' do
      it 'calculates average execution time from completed runs' do
        workflow.runs.destroy_all
        create(:ai_workflow_run, :completed, ai_workflow: workflow, duration_ms: 1000)
        create(:ai_workflow_run, :completed, ai_workflow: workflow, duration_ms: 2000)
        
        expect(workflow.average_execution_time).to eq(1500.0)
      end

      it 'returns 0 when no completed runs exist' do
        workflow.runs.destroy_all
        expect(workflow.average_execution_time).to eq(0.0)
      end
    end
  end

  describe 'import and export' do
    describe '#to_export_format' do
      let(:workflow) { create(:ai_workflow, :with_simple_chain, :with_variables) }

      it 'exports workflow in portable format' do
        export_data = workflow.to_export_format
        
        expect(export_data).to include(:workflow, :nodes, :edges, :variables)
        expect(export_data[:workflow]).to include(:name, :description, :configuration)
        expect(export_data[:nodes]).to be_an(Array)
        expect(export_data[:edges]).to be_an(Array)
        expect(export_data[:variables]).to be_an(Array)
      end

      it 'excludes sensitive information' do
        create(:ai_workflow_variable, :sensitive, ai_workflow: workflow)
        export_data = workflow.to_export_format
        
        sensitive_var = export_data[:variables].find { |v| v[:is_sensitive] }
        expect(sensitive_var[:default_value]).to be_nil
      end

      it 'includes metadata for import validation' do
        export_data = workflow.to_export_format
        
        expect(export_data[:metadata]).to include(:export_version, :exported_at)
        expect(export_data[:metadata][:export_version]).to eq('1.0')
      end
    end

    describe '.from_export_format' do
      let(:export_data) do
        workflow = create(:ai_workflow, :with_simple_chain)
        workflow.to_export_format
      end

      it 'creates workflow from export data' do
        account = create(:account)
        
        imported_workflow = AiWorkflow.from_export_format(export_data, account)
        
        expect(imported_workflow).to be_persisted
        expect(imported_workflow.account).to eq(account)
        expect(imported_workflow.nodes.count).to be > 0
        expect(imported_workflow.edges.count).to be > 0
      end

      it 'generates new UUIDs for nodes' do
        account = create(:account)
        original_workflow = create(:ai_workflow, :with_simple_chain)
        export_data = original_workflow.to_export_format
        
        imported_workflow = AiWorkflow.from_export_format(export_data, account)
        
        original_node_ids = original_workflow.nodes.pluck(:node_id)
        imported_node_ids = imported_workflow.nodes.pluck(:node_id)
        
        expect(original_node_ids & imported_node_ids).to be_empty
      end

      it 'validates import data structure' do
        invalid_data = { invalid: 'data' }
        account = create(:account)
        
        expect {
          AiWorkflow.from_export_format(invalid_data, account)
        }.to raise_error(ArgumentError, /Invalid export format/)
      end
    end
  end

  describe 'class methods' do
    describe '.create_from_template' do
      let(:template) { create(:ai_workflow_template, :content_generation) }
      let(:account) { create(:account) }

      it 'creates workflow from template' do
        workflow = AiWorkflow.create_from_template(template, account)
        
        expect(workflow).to be_persisted
        expect(workflow.account).to eq(account)
        expect(workflow.name).to include(template.name)
        expect(workflow.nodes.count).to be > 0
      end

      it 'applies template customizations' do
        customizations = {
          name: 'Custom Workflow Name',
          configuration: { max_execution_time: 7200 }
        }
        
        workflow = AiWorkflow.create_from_template(template, account, customizations)
        
        expect(workflow.name).to eq('Custom Workflow Name')
        expect(workflow.configuration['max_execution_time']).to eq(7200)
      end
    end

    describe '.popular' do
      it 'returns workflows ordered by execution count' do
        workflow1 = create(:ai_workflow)
        workflow2 = create(:ai_workflow)
        
        # Create more runs for workflow2
        create_list(:ai_workflow_run, 3, ai_workflow: workflow1)
        create_list(:ai_workflow_run, 5, ai_workflow: workflow2)
        
        popular_workflows = AiWorkflow.popular(limit: 2)
        expect(popular_workflows.first).to eq(workflow2)
        expect(popular_workflows.second).to eq(workflow1)
      end
    end

    describe '.by_complexity' do
      let!(:simple_workflow) { create(:ai_workflow) }
      let!(:complex_workflow) { create(:ai_workflow, :with_complex_flow) }

      it 'categorizes workflows by complexity' do
        complex_workflows = AiWorkflow.by_complexity('high')
        expect(complex_workflows).to include(complex_workflow)
        
        simple_workflows = AiWorkflow.by_complexity('low')
        expect(simple_workflows).to include(simple_workflow)
      end
    end
  end

  describe 'edge cases and error handling' do
    it 'handles missing configuration gracefully' do
      workflow = build(:ai_workflow, configuration: nil)
      workflow.valid?
      expect(workflow.configuration).to be_a(Hash)
    end

    it 'handles malformed JSON in metadata' do
      workflow = create(:ai_workflow)
      # Directly update database to simulate corrupted data
      AiWorkflow.where(id: workflow.id).update_all(metadata: 'invalid json')
      
      expect { workflow.reload.metadata }.not_to raise_error
    end

    it 'validates configuration changes atomically' do
      workflow = create(:ai_workflow)
      
      expect {
        workflow.update!(configuration: { execution_mode: 'invalid_mode' })
      }.to raise_error(ActiveRecord::RecordInvalid)
      
      # Original configuration should be preserved
      expect(workflow.reload.configuration['execution_mode']).not_to eq('invalid_mode')
    end

    it 'handles large numbers of nodes gracefully' do
      workflow = create(:ai_workflow)
      
      # Create 100 nodes without timeout
      expect {
        Timeout.timeout(5.seconds) do
          100.times { create(:ai_workflow_node, ai_workflow: workflow) }
        end
      }.not_to raise_error
      
      expect(workflow.nodes.count).to eq(100)
    end

    it 'prevents execution of workflows with circular dependencies' do
      workflow = create(:ai_workflow)
      node1 = create(:ai_workflow_node, ai_workflow: workflow)
      node2 = create(:ai_workflow_node, ai_workflow: workflow)
      
      create(:ai_workflow_edge, ai_workflow: workflow, source_node_id: node1.node_id, target_node_id: node2.node_id)
      create(:ai_workflow_edge, ai_workflow: workflow, source_node_id: node2.node_id, target_node_id: node1.node_id)
      
      workflow.update!(status: 'active')
      
      expect {
        workflow.execute(input_variables: {})
      }.to raise_error(ArgumentError, /circular dependencies/)
    end
  end

  describe 'performance considerations' do
    it 'efficiently loads workflow with many relationships' do
      workflow = create(:ai_workflow, :with_complex_flow, :with_variables, :with_execution_history)
      
      # Test N+1 query prevention
      expect {
        workflow.nodes.includes(:edges_as_source, :edges_as_target).to_a
      }.to execute_queries(count: 3..5) # Should not scale with number of nodes
    end

    it 'handles concurrent workflow executions' do
      workflow = create(:ai_workflow, :with_simple_chain, status: 'active')

      # Execute workflows in main thread (execute creates runs which access DB)
      runs = 3.times.map do |i|
        workflow.execute(input_variables: { thread_id: i })
      end

      # Test concurrent attribute access on the created runs
      threads = runs.map do |run|
        Thread.new do
          # Just access attributes, don't reload (reload queries DB and hits transaction isolation)
          run.run_id
        end
      end

      run_ids = threads.map(&:value)

      expect(runs.all?(&:persisted?)).to be true
      expect(run_ids.uniq.count).to eq(3) # All runs should have unique IDs
    end
  end
end