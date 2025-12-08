# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiWorkflow, type: :model do
  describe 'associations' do
    it { should belong_to(:account) }
    it { should belong_to(:creator).class_name('User') }
    it { should have_many(:ai_workflow_nodes).dependent(:destroy) }
    it { should have_many(:ai_workflow_edges).dependent(:destroy) }
    it { should have_many(:ai_workflow_runs).dependent(:destroy) }
    it { should have_many(:ai_workflow_variables).dependent(:destroy) }
    it { should have_many(:ai_workflow_schedules).dependent(:destroy) }
    it { should have_many(:ai_workflow_triggers).dependent(:destroy) }
    it { should have_many(:ai_workflow_template_installations).dependent(:destroy) }

    # Alias associations
    it { should have_many(:nodes).class_name('AiWorkflowNode').dependent(:destroy) }
    it { should have_many(:edges).class_name('AiWorkflowEdge').dependent(:destroy) }
    it { should have_many(:runs).class_name('AiWorkflowRun').dependent(:destroy) }
    it { should have_many(:variables).class_name('AiWorkflowVariable').dependent(:destroy) }
    it { should have_many(:schedules).class_name('AiWorkflowSchedule').dependent(:destroy) }
    it { should have_many(:triggers).class_name('AiWorkflowTrigger').dependent(:destroy) }
  end

  describe 'validations' do
    subject { build(:ai_workflow) }

    it { should validate_presence_of(:name) }
    it { should validate_length_of(:name).is_at_most(255) }
    it { should validate_length_of(:description).is_at_most(1000) }
    it { should validate_inclusion_of(:status).in_array(%w[draft active paused inactive archived]) }
    it { should allow_value('1.0.0', '2.1.3', '10.20.30').for(:version) }
    it { should_not allow_value('1.0', '1.0.0.1', 'invalid').for(:version) }

    context 'slug validation' do
      it 'auto-generates slug from name' do
        workflow = build(:ai_workflow, name: 'My Test Workflow', slug: nil)
        workflow.valid?
        expect(workflow.slug).to be_present
        expect(workflow.slug).to match(/my-test-workflow/)
      end

      it 'validates slug format' do
        # Create workflow first, then update slug directly to bypass callback
        workflow = create(:ai_workflow)
        # Use update_column to bypass callbacks and validations
        workflow.update_column(:slug, 'Invalid Slug!')
        workflow.reload
        expect(workflow).not_to be_valid
        expect(workflow.errors[:slug]).to be_present
      end
    end

    context 'version uniqueness' do
      let!(:existing_workflow) { create(:ai_workflow) }

      it 'validates uniqueness of version within account and name scope' do
        duplicate_workflow = build(:ai_workflow,
                                   name: existing_workflow.name,
                                   version: existing_workflow.version,
                                   account: existing_workflow.account)

        expect(duplicate_workflow).not_to be_valid
        expect(duplicate_workflow.errors[:version]).to be_present
      end

      it 'allows same version for different workflow names' do
        workflow_with_same_version = build(:ai_workflow,
                                           name: 'Different Workflow',
                                           version: existing_workflow.version,
                                           account: existing_workflow.account)

        expect(workflow_with_same_version).to be_valid
      end
    end

    context 'configuration validation' do
      it 'validates configuration is present' do
        workflow = build(:ai_workflow)
        workflow.configuration = nil
        expect(workflow).not_to be_valid
      end

      it 'validates execution_mode if present' do
        workflow = build(:ai_workflow, configuration: { 'execution_mode' => 'invalid' })
        expect(workflow).not_to be_valid
        expect(workflow.errors[:configuration]).to include('invalid execution_mode')
      end

      it 'accepts valid execution modes' do
        %w[sequential parallel conditional batch].each do |mode|
          workflow = build(:ai_workflow, configuration: { 'execution_mode' => mode })
          workflow.valid?
          expect(workflow.errors[:configuration]).not_to include('invalid execution_mode')
        end
      end

      it 'validates max_execution_time is positive' do
        workflow = build(:ai_workflow, configuration: { 'max_execution_time' => -100 })
        expect(workflow).not_to be_valid
        expect(workflow.errors[:configuration]).to include('max_execution_time must be positive')
      end
    end

    context 'template validation' do
      it 'requires template_category for templates' do
        workflow = build(:ai_workflow, is_template: true, template_category: nil)
        expect(workflow).not_to be_valid
        expect(workflow.errors[:template_category]).to be_present
      end

      it 'requires description for templates' do
        workflow = build(:ai_workflow, is_template: true, description: nil)
        expect(workflow).not_to be_valid
        expect(workflow.errors[:description]).to be_present
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
        expect(described_class.active).to include(active_workflow)
        expect(described_class.active).not_to include(draft_workflow, paused_workflow, archived_workflow)
      end
    end

    describe '.draft' do
      it 'returns only draft workflows' do
        expect(described_class.draft).to include(draft_workflow)
        expect(described_class.draft).not_to include(active_workflow)
      end
    end

    describe '.paused' do
      it 'returns only paused workflows' do
        expect(described_class.paused).to include(paused_workflow)
        expect(described_class.paused).not_to include(active_workflow)
      end
    end

    describe '.archived' do
      it 'returns only archived workflows' do
        expect(described_class.archived).to include(archived_workflow)
        expect(described_class.archived).not_to include(active_workflow)
      end
    end

    describe '.executable' do
      it 'returns workflows that can be executed' do
        expect(described_class.executable).to include(active_workflow, paused_workflow)
        expect(described_class.executable).not_to include(draft_workflow, archived_workflow)
      end
    end

    describe '.by_status' do
      it 'filters workflows by status' do
        expect(described_class.by_status('active')).to include(active_workflow)
        expect(described_class.by_status('draft')).to include(draft_workflow)
      end
    end

    describe '.search' do
      let!(:workflow1) { create(:ai_workflow, name: 'Data Processing Pipeline') }
      let!(:workflow2) { create(:ai_workflow, name: 'Blog Generator', description: 'Content creation workflow') }

      it 'searches by name' do
        results = described_class.search('Data')
        expect(results).to include(workflow1)
        expect(results).not_to include(workflow2)
      end

      it 'searches by description' do
        results = described_class.search('Content')
        expect(results).to include(workflow2)
        expect(results).not_to include(workflow1)
      end

      it 'returns all workflows for empty query' do
        results = described_class.search('')
        expect(results.count).to be >= 2
      end
    end

    describe '.recent' do
      let!(:old_workflow) { create(:ai_workflow, created_at: 2.months.ago) }
      let!(:recent_workflow) { create(:ai_workflow, created_at: 1.day.ago) }

      it 'returns workflows from specified time period' do
        results = described_class.recent(1.week)
        expect(results).to include(recent_workflow)
        expect(results).not_to include(old_workflow)
      end
    end

    describe '.templates' do
      let!(:template) { create(:ai_workflow, is_template: true, template_category: 'general') }
      let!(:workflow) { create(:ai_workflow, is_template: false) }

      it 'returns only templates' do
        expect(described_class.templates).to include(template)
        expect(described_class.templates).not_to include(workflow)
      end
    end

    describe '.workflows' do
      let!(:template) { create(:ai_workflow, is_template: true, template_category: 'general') }
      let!(:workflow) { create(:ai_workflow, is_template: false) }

      it 'returns only non-templates' do
        expect(described_class.workflows).to include(workflow)
        expect(described_class.workflows).not_to include(template)
      end
    end
  end

  describe 'callbacks' do
    describe 'before_validation' do
      it 'generates slug from name' do
        workflow = build(:ai_workflow, name: 'Test Workflow', slug: nil)
        workflow.valid?
        expect(workflow.slug).to be_present
      end

      it 'generates unique slug when duplicate exists' do
        existing = create(:ai_workflow, name: 'Test Workflow')
        new_workflow = build(:ai_workflow, name: 'Test Workflow', account: existing.account, slug: nil)
        new_workflow.valid?
        expect(new_workflow.slug).to be_present
        expect(new_workflow.slug).not_to eq(existing.slug)
      end
    end

    describe 'before_save' do
      it 'increments version when configuration changes' do
        workflow = create(:ai_workflow, version: '1.0.0')
        original_version = workflow.version

        workflow.update!(configuration: workflow.configuration.merge('new_setting' => true))

        expect(workflow.version).not_to eq(original_version)
      end
    end
  end

  describe 'status check methods' do
    describe '#active?' do
      it 'returns true for active status' do
        workflow = build(:ai_workflow, status: 'active')
        expect(workflow.active?).to be true
      end

      it 'returns false for other statuses' do
        workflow = build(:ai_workflow, status: 'draft')
        expect(workflow.active?).to be false
      end
    end

    describe '#draft?' do
      it 'returns true for draft status' do
        workflow = build(:ai_workflow, status: 'draft')
        expect(workflow.draft?).to be true
      end
    end

    describe '#paused?' do
      it 'returns true for paused status' do
        workflow = build(:ai_workflow, status: 'paused')
        expect(workflow.paused?).to be true
      end
    end

    describe '#archived?' do
      it 'returns true for archived status' do
        workflow = build(:ai_workflow, status: 'archived')
        expect(workflow.archived?).to be true
      end
    end

    describe '#inactive?' do
      it 'returns true for inactive status' do
        workflow = build(:ai_workflow, status: 'inactive')
        expect(workflow.inactive?).to be true
      end
    end
  end

  describe 'workflow execution' do
    let(:workflow) { create(:ai_workflow, :with_simple_chain) }

    describe '#can_execute?' do
      it 'returns true for active workflows with valid structure' do
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

      it 'returns false for workflows without nodes' do
        empty_workflow = create(:ai_workflow, status: 'active')
        expect(empty_workflow.can_execute?).to be false
      end
    end

    describe '#can_edit?' do
      it 'returns true for draft workflows' do
        workflow = build(:ai_workflow, status: 'draft')
        expect(workflow.can_edit?).to be true
      end

      it 'returns true for paused workflows' do
        workflow = build(:ai_workflow, status: 'paused')
        expect(workflow.can_edit?).to be true
      end

      it 'returns false for active workflows' do
        workflow = build(:ai_workflow, status: 'active')
        expect(workflow.can_edit?).to be false
      end
    end

    describe '#can_delete?' do
      it 'returns true when no active runs exist' do
        workflow = create(:ai_workflow)
        expect(workflow.can_delete?).to be true
      end

      it 'returns false when running executions exist' do
        workflow = create(:ai_workflow)
        create(:ai_workflow_run, :running, ai_workflow: workflow)
        expect(workflow.can_delete?).to be false
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
        end

        it 'updates last_executed_at timestamp' do
          expect {
            workflow.execute(input_variables: {})
          }.to change { workflow.reload.last_executed_at }
        end

        it 'increments execution_count' do
          expect {
            workflow.execute(input_variables: {})
          }.to change { workflow.reload.execution_count }.by(1)
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
    end
  end

  describe 'workflow structure validation' do
    describe '#has_valid_structure?' do
      it 'returns true for workflow with start node and no cycles' do
        workflow = create(:ai_workflow, :with_simple_chain)
        expect(workflow.has_valid_structure?).to be true
      end

      it 'returns false for workflow without start node' do
        workflow = create(:ai_workflow)
        create(:ai_workflow_node, ai_workflow: workflow, is_start_node: false)
        expect(workflow.has_valid_structure?).to be false
      end
    end

    describe '#validate_structure' do
      it 'returns hash with validation results' do
        workflow = create(:ai_workflow, :with_simple_chain)
        result = workflow.validate_structure

        expect(result).to be_a(Hash)
        expect(result).to have_key(:valid)
        expect(result).to have_key(:errors)
        expect(result).to have_key(:warnings)
      end

      it 'returns valid: true for valid workflow' do
        workflow = create(:ai_workflow, :with_simple_chain)
        result = workflow.validate_structure

        expect(result[:valid]).to be true
        expect(result[:errors]).to be_empty
      end

      it 'returns errors for workflow without start node' do
        workflow = create(:ai_workflow)
        create(:ai_workflow_node, ai_workflow: workflow, is_start_node: false, is_end_node: true)

        result = workflow.validate_structure

        expect(result[:valid]).to be false
        expect(result[:errors]).to include('Workflow must have at least one node marked as a start node')
      end

      it 'returns warnings for workflow without end nodes' do
        workflow = create(:ai_workflow)
        create(:ai_workflow_node, ai_workflow: workflow, is_start_node: true, is_end_node: false)

        result = workflow.validate_structure

        expect(result[:warnings]).to include(/no end nodes/)
      end
    end

    describe '#start_nodes' do
      it 'returns nodes marked as start nodes' do
        workflow = create(:ai_workflow)
        start_node = create(:ai_workflow_node, ai_workflow: workflow, is_start_node: true)
        create(:ai_workflow_node, ai_workflow: workflow, is_start_node: false)

        expect(workflow.start_nodes).to include(start_node)
        expect(workflow.start_nodes.count).to eq(1)
      end
    end

    describe '#end_nodes' do
      it 'returns nodes marked as end nodes' do
        workflow = create(:ai_workflow)
        end_node = create(:ai_workflow_node, ai_workflow: workflow, is_end_node: true)
        create(:ai_workflow_node, ai_workflow: workflow, is_end_node: false)

        expect(workflow.end_nodes).to include(end_node)
        expect(workflow.end_nodes.count).to eq(1)
      end
    end

    describe '#node_count' do
      it 'returns count of workflow nodes' do
        workflow = create(:ai_workflow)
        create_list(:ai_workflow_node, 3, ai_workflow: workflow)

        expect(workflow.node_count).to eq(3)
      end
    end

    describe '#edge_count' do
      it 'returns count of workflow edges' do
        workflow = create(:ai_workflow, :with_simple_chain)
        expect(workflow.edge_count).to be > 0
      end
    end
  end

  describe 'state management' do
    describe '#publish!' do
      let(:workflow) { create(:ai_workflow, :with_simple_chain, status: 'draft') }

      it 'changes status to active' do
        workflow.publish!
        expect(workflow.status).to eq('active')
      end

      it 'sets published_at timestamp' do
        workflow.publish!
        expect(workflow.published_at).to be_present
      end

      it 'returns false for invalid workflow' do
        empty_workflow = create(:ai_workflow, status: 'draft')
        result = empty_workflow.publish!
        expect(result).to be false
      end
    end

    describe '#pause!' do
      let(:workflow) { create(:ai_workflow, status: 'active') }

      it 'changes status to paused' do
        workflow.pause!
        expect(workflow.status).to eq('paused')
      end

      it 'stores paused_at in metadata' do
        workflow.pause!
        expect(workflow.metadata['paused_at']).to be_present
      end
    end

    describe '#archive!' do
      let(:workflow) { create(:ai_workflow, status: 'active') }

      it 'changes status to archived' do
        workflow.archive!
        expect(workflow.status).to eq('archived')
      end

      it 'stores archived_at in metadata' do
        workflow.archive!
        expect(workflow.metadata['archived_at']).to be_present
      end

      it 'deactivates related schedules' do
        schedule = create(:ai_workflow_schedule, ai_workflow: workflow, is_active: true, status: 'active')
        workflow.archive!
        expect(schedule.reload.is_active).to be false
      end
    end
  end

  describe 'duplication' do
    describe '#duplicate' do
      let(:original) { create(:ai_workflow, :with_simple_chain, :with_variables) }

      it 'creates a copy of the workflow' do
        duplicate = original.duplicate

        expect(duplicate.name).to eq("#{original.name} (Copy)")
        expect(duplicate.status).to eq('draft')
        expect(duplicate).to be_persisted
      end

      it 'duplicates nodes with new IDs' do
        duplicate = original.duplicate

        expect(duplicate.nodes.count).to eq(original.nodes.count)

        original_node_ids = original.nodes.pluck(:node_id)
        duplicate_node_ids = duplicate.nodes.pluck(:node_id)

        expect(original_node_ids & duplicate_node_ids).to be_empty
      end

      it 'duplicates edges with updated node references' do
        duplicate = original.duplicate
        expect(duplicate.edges.count).to eq(original.edges.count)
      end

      it 'duplicates variables' do
        duplicate = original.duplicate
        expect(duplicate.variables.count).to eq(original.variables.count)
      end

      it 'stores duplication metadata' do
        duplicate = original.duplicate
        expect(duplicate.metadata['duplicated_from']).to eq(original.id)
        expect(duplicate.metadata['duplicated_at']).to be_present
      end
    end

    describe '#duplicate_for_account' do
      let(:target_account) { create(:account) }

      it 'creates workflow in target account' do
        # Create a simple workflow without external references (no agent_id)
        source_account = create(:account)
        source_user = create(:user, account: source_account)
        original = create(:ai_workflow, account: source_account, creator: source_user)

        # Add simple nodes without agent references
        start_node = create(:ai_workflow_node, ai_workflow: original, node_type: 'start', is_start_node: true, configuration: {})
        end_node = create(:ai_workflow_node, ai_workflow: original, node_type: 'end', is_end_node: true, configuration: {})
        create(:ai_workflow_edge, ai_workflow: original, source_node_id: start_node.node_id, target_node_id: end_node.node_id)

        # Create user in target account for creator assignment
        target_user = create(:user, account: target_account)
        duplicate = original.duplicate_for_account(target_account, target_user)

        expect(duplicate.account).to eq(target_account)
        expect(duplicate.creator).to eq(target_user)
      end
    end
  end

  describe 'statistics and metrics' do
    let(:workflow) { create(:ai_workflow) }

    describe '#execution_stats' do
      before do
        create_list(:ai_workflow_run, 3, :completed, ai_workflow: workflow)
        create(:ai_workflow_run, :failed, ai_workflow: workflow)
      end

      it 'calculates execution statistics' do
        stats = workflow.execution_stats

        expect(stats).to include(:total_executions)
        expect(stats).to include(:successful_executions)
        expect(stats).to include(:failed_executions)
        expect(stats).to include(:success_rate)
        expect(stats[:total_executions]).to eq(4)
      end

      it 'calculates success rate correctly' do
        stats = workflow.execution_stats
        expect(stats[:success_rate]).to eq(75.0)
      end
    end

    describe '#execution_summary' do
      it 'returns comprehensive summary' do
        summary = workflow.execution_summary

        expect(summary).to include(:total_executions)
        expect(summary).to include(:success_rate)
        expect(summary).to include(:average_duration)
        expect(summary).to include(:last_execution)
        expect(summary).to include(:total_cost)
        expect(summary).to include(:status_breakdown)
      end
    end

    describe '#recent_runs' do
      it 'returns runs from specified period' do
        old_run = create(:ai_workflow_run, ai_workflow: workflow, created_at: 2.days.ago)
        recent_run = create(:ai_workflow_run, ai_workflow: workflow, created_at: 1.hour.ago)

        recent = workflow.recent_runs(24.hours)
        expect(recent).to include(recent_run)
        expect(recent).not_to include(old_run)
      end
    end

    describe '#total_cost' do
      it 'sums cost from completed runs' do
        create(:ai_workflow_run, :completed, ai_workflow: workflow)
        # Use update_column to set total_cost since factory may reset it
        workflow.ai_workflow_runs.update_all(total_cost: 0.05)

        expect(workflow.total_cost).to eq(0.05)
      end

      it 'returns 0 when no runs exist' do
        expect(workflow.total_cost).to eq(0.0)
      end
    end

    describe '#average_execution_time' do
      it 'calculates average from completed runs' do
        create(:ai_workflow_run, :completed, ai_workflow: workflow, duration_ms: 1000)
        create(:ai_workflow_run, :completed, ai_workflow: workflow, duration_ms: 2000)

        expect(workflow.average_execution_time).to eq(1500.0)
      end

      it 'returns 0 when no completed runs exist' do
        expect(workflow.average_execution_time).to eq(0.0)
      end
    end
  end

  describe 'timeout functionality' do
    let(:workflow) { create(:ai_workflow) }

    describe '#timeout_seconds' do
      it 'returns max_execution_time from configuration' do
        workflow.configuration['max_execution_time'] = 7200
        expect(workflow.timeout_seconds).to eq(7200)
      end

      it 'returns default when not configured' do
        workflow.configuration.delete('max_execution_time')
        expect(workflow.timeout_seconds).to eq(3600)
      end
    end

    describe '#timeout_minutes' do
      it 'returns timeout in minutes' do
        workflow.configuration['max_execution_time'] = 3600
        expect(workflow.timeout_minutes).to eq(60.0)
      end
    end

    describe '#timeout_minutes=' do
      it 'sets timeout from minutes' do
        workflow.timeout_minutes = 30
        expect(workflow.configuration['max_execution_time']).to eq(1800)
      end
    end
  end

  describe 'versioning' do
    let(:workflow) { create(:ai_workflow, version: '1.0.0') }

    describe '#version_number' do
      it 'returns Gem::Version object' do
        expect(workflow.version_number).to be_a(Gem::Version)
        expect(workflow.version_number.to_s).to eq('1.0.0')
      end
    end

    describe '#newer_than?' do
      it 'compares versions correctly' do
        older_workflow = create(:ai_workflow, version: '0.9.0', name: 'Different')
        newer_workflow = create(:ai_workflow, version: '2.0.0', name: 'Another')

        expect(workflow.newer_than?(older_workflow)).to be true
        expect(workflow.newer_than?(newer_workflow)).to be false
      end
    end

    describe '#all_versions' do
      it 'returns all versions of the workflow' do
        account = create(:account)
        user = create(:user, account: account)
        v1 = create(:ai_workflow, name: 'Test Workflow', version: '1.0.0', account: account, creator: user, is_active: true)
        # Second version needs is_active: false to avoid "only one active version" validation
        v2 = create(:ai_workflow, name: 'Test Workflow', version: '1.0.1', account: account, creator: user, is_active: false)

        versions = v1.all_versions
        expect(versions).to include(v1, v2)
      end
    end
  end

  describe 'import functionality' do
    describe '.import_from_data' do
      let(:account) { create(:account) }
      let(:user) { create(:user, account: account) }
      let(:import_data) do
        {
          workflow: {
            name: 'Imported Workflow',
            description: 'A test workflow',
            status: 'draft',
            visibility: 'private',
            configuration: { 'execution_mode' => 'sequential' }
          },
          nodes: [
            {
              node_id: 'original-node-1',
              node_type: 'start',
              name: 'Start',
              is_start_node: true,
              position: { x: 0, y: 0 }
            },
            {
              node_id: 'original-node-2',
              node_type: 'end',
              name: 'End',
              is_end_node: true,
              position: { x: 100, y: 0 }
            }
          ],
          edges: [
            {
              source_node_id: 'original-node-1',
              target_node_id: 'original-node-2',
              edge_type: 'default'
            }
          ]
        }
      end

      it 'creates workflow from import data' do
        workflow = described_class.import_from_data(import_data, account, user)

        expect(workflow).to be_persisted
        expect(workflow.name).to eq('Imported Workflow')
        expect(workflow.account).to eq(account)
        expect(workflow.creator).to eq(user)
      end

      it 'creates nodes with new IDs' do
        workflow = described_class.import_from_data(import_data, account, user)

        expect(workflow.nodes.count).to eq(2)
        node_ids = workflow.nodes.pluck(:node_id)
        expect(node_ids).not_to include('original-node-1', 'original-node-2')
      end

      it 'creates edges with updated node references' do
        workflow = described_class.import_from_data(import_data, account, user)

        expect(workflow.edges.count).to eq(1)
        edge = workflow.edges.first
        expect(workflow.nodes.pluck(:node_id)).to include(edge.source_node_id, edge.target_node_id)
      end

      it 'allows name override' do
        workflow = described_class.import_from_data(import_data, account, user, name_override: 'Custom Name')
        expect(workflow.name).to eq('Custom Name')
      end
    end
  end

  describe 'edge cases' do
    it 'handles configuration changes atomically' do
      workflow = create(:ai_workflow)

      expect {
        workflow.update!(configuration: { 'execution_mode' => 'invalid_mode' })
      }.to raise_error(ActiveRecord::RecordInvalid)

      expect(workflow.reload.configuration['execution_mode']).not_to eq('invalid_mode')
    end

    it 'prevents deletion with recent runs' do
      workflow = create(:ai_workflow)
      create(:ai_workflow_run, ai_workflow: workflow, created_at: 1.minute.ago)

      expect(workflow.can_delete?).to be false
    end
  end
end
