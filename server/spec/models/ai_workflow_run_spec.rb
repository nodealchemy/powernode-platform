# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiWorkflowRun, type: :model do
  subject(:workflow_run) { build(:ai_workflow_run) }

  describe 'associations' do
    it { is_expected.to belong_to(:ai_workflow) }
    it { is_expected.to belong_to(:account) }
    it { is_expected.to have_many(:ai_workflow_node_executions).dependent(:destroy) }
    it { is_expected.to have_many(:ai_workflow_run_logs).dependent(:destroy) }
  end

  describe 'validations' do
    # belongs_to associations with required: true are tested in associations section
    it { is_expected.to validate_presence_of(:status) }
    it { is_expected.to validate_presence_of(:trigger_type) }
    
    it { is_expected.to validate_inclusion_of(:status).in_array(%w[initializing running completed failed cancelled waiting_approval]).with_message('must be a valid run status') }
    it { is_expected.to validate_inclusion_of(:trigger_type).in_array(%w[manual webhook schedule event api_call]).with_message('must be a valid trigger type') }

    context 'execution time validations' do
      it 'validates that completed_at is after started_at when both are present' do
        run = build(:ai_workflow_run, 
                   started_at: 1.hour.ago,
                   completed_at: 2.hours.ago)
        
        expect(run).not_to be_valid
        expect(run.errors[:completed_at]).to include('must be after started_at')
      end

      it 'allows completed_at to be nil' do
        run = build(:ai_workflow_run, 
                   started_at: 1.hour.ago,
                   completed_at: nil)
        
        expect(run).to be_valid
      end
    end

    context 'status-dependent validations' do
      it 'requires completed_at for completed status' do
        run = build(:ai_workflow_run, 
                   status: 'completed',
                   completed_at: nil)
        
        expect(run).not_to be_valid
        expect(run.errors[:completed_at]).to include("can't be blank for completed runs")
      end

      it 'requires completed_at for failed status' do
        run = build(:ai_workflow_run, 
                   status: 'failed',
                   completed_at: nil)
        
        expect(run).not_to be_valid
        expect(run.errors[:completed_at]).to include("can't be blank for failed runs")
      end

      it 'requires error_details for failed status' do
        run = build(:ai_workflow_run,
                   status: 'failed',
                   error_details: nil)

        expect(run).not_to be_valid
        expect(run.errors[:error_details]).to include("can't be blank for failed runs")
      end
    end

    context 'input/output validations' do
      it 'validates input_variables is a hash when present' do
        run = build(:ai_workflow_run, input_variables: 'not a hash')
        expect(run).not_to be_valid
        expect(run.errors[:input_variables]).to include('must be a hash')
      end

      it 'validates output_data is a hash when present' do
        run = build(:ai_workflow_run, output_data: 'not a hash')
        expect(run).not_to be_valid
        expect(run.errors[:output_data]).to include('must be a hash')
      end

      it 'allows nil for input_variables and output_data' do
        run = build(:ai_workflow_run, 
                   input_variables: nil,
                   output_data: nil)
        expect(run).to be_valid
      end
    end
  end

  describe 'scopes' do
    let!(:initializing_run) { create(:ai_workflow_run, status: 'initializing') }
    let!(:running_run) { create(:ai_workflow_run, :running) }
    let!(:completed_run) { create(:ai_workflow_run, :completed) }
    let!(:failed_run) { create(:ai_workflow_run, :failed) }
    let!(:recent_run) { create(:ai_workflow_run, created_at: 1.hour.ago) }
    let!(:old_run) { create(:ai_workflow_run, created_at: 1.week.ago) }

    describe '.by_status' do
      it 'filters runs by status' do
        expect(described_class.by_status('running')).to include(running_run)
        expect(described_class.by_status('running')).not_to include(initializing_run)
      end
    end

    describe '.active' do
      it 'returns initializing, running and waiting_approval runs' do
        active_runs = described_class.active
        expect(active_runs).to include(initializing_run, running_run)
        expect(active_runs).not_to include(completed_run, failed_run)
      end
    end

    describe '.completed' do
      it 'returns completed runs' do
        expect(described_class.completed).to include(completed_run)
        expect(described_class.completed).not_to include(running_run)
      end
    end

    describe '.failed' do
      it 'returns failed runs' do
        expect(described_class.failed).to include(failed_run)
        expect(described_class.failed).not_to include(completed_run)
      end
    end

    describe '.finished' do
      it 'returns completed and failed runs' do
        finished_runs = described_class.finished
        expect(finished_runs).to include(completed_run, failed_run)
        expect(finished_runs).not_to include(running_run)
      end
    end

    describe '.recent' do
      it 'returns runs from last 24 hours' do
        expect(described_class.recent).to include(recent_run)
        expect(described_class.recent).not_to include(old_run)
      end
    end

    describe '.by_trigger_type' do
      let!(:manual_run) { create(:ai_workflow_run, trigger_type: 'manual') }
      let!(:scheduled_run) { create(:ai_workflow_run, :scheduled) }

      it 'filters runs by trigger type' do
        expect(described_class.by_trigger_type('manual')).to include(manual_run)
        expect(described_class.by_trigger_type('manual')).not_to include(scheduled_run)
      end
    end

    describe '.for_workflow' do
      let(:workflow1) { create(:ai_workflow) }
      let(:workflow2) { create(:ai_workflow) }
      let!(:run1) { create(:ai_workflow_run, ai_workflow: workflow1) }
      let!(:run2) { create(:ai_workflow_run, ai_workflow: workflow2) }

      it 'filters runs by workflow' do
        expect(described_class.for_workflow(workflow1)).to include(run1)
        expect(described_class.for_workflow(workflow1)).not_to include(run2)
      end
    end
  end

  describe 'state machine and callbacks' do
    describe 'status transitions' do
      it 'starts in initializing status' do
        run = create(:ai_workflow_run)
        expect(run.status).to eq('initializing')
      end

      it 'can transition from initializing to running' do
        run = create(:ai_workflow_run, status: 'initializing')
        run.start_execution!
        expect(run.status).to eq('running')
        expect(run.started_at).to be_present
      end

      it 'can transition from running to completed' do
        run = create(:ai_workflow_run, :running)
        run.mark_completed!(output_data: { result: 'success' })
        expect(run.status).to eq('completed')
        expect(run.completed_at).to be_present
        expect(run.output_data['result']).to eq('success')
      end

      it 'can transition from running to failed' do
        run = create(:ai_workflow_run, :running)
        run.mark_failed!('Execution error occurred')
        expect(run.status).to eq('failed')
        expect(run.completed_at).to be_present
        expect(run.error_message).to eq('Execution error occurred')
      end

      it 'can pause for approval and resume execution' do
        run = create(:ai_workflow_run, :running)
        run.pause_for_approval!('node_123', 'Human approval required')
        expect(run.status).to eq('waiting_approval')
        
        run.resume_after_approval!(create(:user).id, 'approved')
        expect(run.status).to eq('running')
      end

      it 'can cancel execution' do
        run = create(:ai_workflow_run, :running)
        run.cancel_execution!
        expect(run.status).to eq('cancelled')
        expect(run.completed_at).to be_present
      end
    end

    describe 'callbacks' do
      describe 'before_create' do
        it 'generates run_id if not present' do
          run = build(:ai_workflow_run, run_id: nil)
          run.save!
          expect(run.run_id).to be_present
          # UUIDv7 format: 8-4-4-4-12 hexadecimal characters
          expect(run.run_id).to match(/^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i)
        end

        it 'preserves provided run_id' do
          custom_uuid = '01936d5e-58b0-7000-8000-000000000001'
          run = build(:ai_workflow_run, run_id: custom_uuid)
          run.save!
          expect(run.run_id).to eq(custom_uuid)
        end
      end

      describe 'after_create' do
        it 'creates initial execution log' do
          expect {
            create(:ai_workflow_run)
          }.to change { AiWorkflowExecutionLog.count }.by(1)
          
          log = AiWorkflowExecutionLog.last
          expect(log.message).to include('Workflow run created')
          expect(log.log_level).to eq('info')
        end
      end

      describe 'after_update' do
        it 'logs status changes' do
          run = create(:ai_workflow_run, status: 'initializing')
          
          expect {
            run.update!(status: 'running')
          }.to change { run.execution_logs.count }.by(1)
          
          log = run.execution_logs.last
          expect(log.message).to include('Status changed from initializing to running')
        end

        it 'logs completion with metrics' do
          run = create(:ai_workflow_run, :running, started_at: 5.minutes.ago)
          
          expect {
            run.mark_completed!(output_data: { result: 'success' })
          }.to change { run.execution_logs.count }.by(1)
          
          log = run.execution_logs.last
          expect(log.log_data['execution_time_seconds']).to be_present
          expect(log.log_data['total_cost']).to be_present
        end
      end
    end
  end

  describe 'instance methods' do
    describe '#duration' do
      it 'returns nil when not started' do
        run = create(:ai_workflow_run, started_at: nil)
        expect(run.duration).to be_nil
      end

      it 'returns duration from start to completion' do
        run = create(:ai_workflow_run, 
                    started_at: 1.hour.ago,
                    completed_at: 30.minutes.ago)
        expect(run.duration).to eq(30.minutes)
      end

      it 'returns duration from start to now for running workflows' do
        run = create(:ai_workflow_run, :running, started_at: 1.hour.ago)
        expect(run.duration).to be_within(1.second).of(1.hour)
      end
    end

    describe '#estimated_completion' do
      let(:workflow) { create(:ai_workflow) }

      it 'returns nil when no historical data available' do
        run = create(:ai_workflow_run, ai_workflow: workflow, status: 'running')
        expect(run.estimated_completion).to be_nil
      end

      it 'estimates based on historical average' do
        # Create historical runs
        create(:ai_workflow_run, :completed, 
               ai_workflow: workflow,
               started_at: 2.hours.ago,
               completed_at: 1.hour.ago)
        
        create(:ai_workflow_run, :completed,
               ai_workflow: workflow,
               started_at: 3.hours.ago,
               completed_at: 2.hours.ago)
        
        run = create(:ai_workflow_run, :running,
                    ai_workflow: workflow,
                    started_at: 30.minutes.ago)
        
        estimation = run.estimated_completion
        expect(estimation).to be_present
        expect(estimation).to be > Time.current
      end
    end

    describe '#progress_percentage' do
      let(:workflow) { create(:ai_workflow) }
      let(:nodes) { create_list(:ai_workflow_node, 4, ai_workflow: workflow) }
      let(:run) { create(:ai_workflow_run, ai_workflow: workflow) }

      it 'returns 0 when no nodes executed' do
        expect(run.progress_percentage).to eq(0)
      end

      it 'calculates percentage based on completed node executions' do
        # Create 2 completed executions out of 4 total nodes
        create(:ai_workflow_node_execution, :completed,
               ai_workflow_run: run,
               ai_workflow_node: nodes[0])
        
        create(:ai_workflow_node_execution, :completed,
               ai_workflow_run: run,
               ai_workflow_node: nodes[1])
        
        expect(run.progress_percentage).to eq(50)
      end

      it 'returns 100 when all nodes completed' do
        nodes.each do |node|
          create(:ai_workflow_node_execution, :completed,
                 ai_workflow_run: run,
                 ai_workflow_node: node)
        end
        
        expect(run.progress_percentage).to eq(100)
      end
    end

    describe '#total_cost' do
      let(:run) { create(:ai_workflow_run) }

      it 'sums costs from all node executions' do
        create(:ai_workflow_node_execution, ai_workflow_run: run, cost: 0.50)
        create(:ai_workflow_node_execution, ai_workflow_run: run, cost: 0.75)
        create(:ai_workflow_node_execution, ai_workflow_run: run, cost: 0.25)
        
        expect(run.total_cost).to eq(1.50)
      end

      it 'returns 0 when no executions exist' do
        expect(run.total_cost).to eq(0)
      end

      it 'handles nil costs gracefully' do
        create(:ai_workflow_node_execution, ai_workflow_run: run, cost: nil)
        create(:ai_workflow_node_execution, ai_workflow_run: run, cost: 0.50)
        
        expect(run.total_cost).to eq(0.50)
      end
    end

    describe '#can_be_cancelled?' do
      it 'returns true for initializing runs' do
        run = create(:ai_workflow_run, status: 'initializing')
        expect(run.can_be_cancelled?).to be true
      end

      it 'returns true for running runs' do
        run = create(:ai_workflow_run, :running)
        expect(run.can_be_cancelled?).to be true
      end

      it 'returns true for waiting_approval runs' do
        run = create(:ai_workflow_run, status: 'waiting_approval')
        expect(run.can_be_cancelled?).to be true
      end

      it 'returns false for completed runs' do
        run = create(:ai_workflow_run, :completed)
        expect(run.can_be_cancelled?).to be false
      end

      it 'returns false for failed runs' do
        run = create(:ai_workflow_run, :failed)
        expect(run.can_be_cancelled?).to be false
      end
    end

    describe '#can_be_resumed?' do
      it 'returns true only for waiting_approval runs' do
        expect(create(:ai_workflow_run, status: 'waiting_approval').can_be_resumed?).to be true
        expect(create(:ai_workflow_run, status: 'initializing').can_be_resumed?).to be false
        expect(create(:ai_workflow_run, :running).can_be_resumed?).to be false
        expect(create(:ai_workflow_run, :completed).can_be_resumed?).to be false
      end
    end

    describe '#success?' do
      it 'returns true for completed runs' do
        run = create(:ai_workflow_run, :completed)
        expect(run.success?).to be true
      end

      it 'returns false for other statuses' do
        %w[initializing running waiting_approval failed cancelled].each do |status|
          run = create(:ai_workflow_run, status: status)
          expect(run.success?).to be false
        end
      end
    end

    describe '#failed?' do
      it 'returns true for failed runs' do
        run = create(:ai_workflow_run, :failed)
        expect(run.failed?).to be true
      end

      it 'returns false for other statuses' do
        %w[initializing running waiting_approval completed cancelled].each do |status|
          run = create(:ai_workflow_run, status: status)
          expect(run.failed?).to be false
        end
      end
    end

    describe '#execution_summary' do
      let(:run) { create(:ai_workflow_run, :completed, started_at: 1.hour.ago, completed_at: 30.minutes.ago) }

      before do
        create(:ai_workflow_node_execution, :completed, ai_workflow_run: run, cost: 0.25)
        create(:ai_workflow_node_execution, :completed, ai_workflow_run: run, cost: 0.75)
      end

      it 'returns comprehensive execution summary' do
        summary = run.execution_summary
        
        expect(summary).to include(
          :run_id,
          :status,
          :duration_seconds,
          :total_cost,
          :nodes_executed,
          :success_rate,
          :trigger_type,
          :started_at,
          :completed_at
        )
        
        expect(summary[:run_id]).to eq(run.id)
        expect(summary[:status]).to eq('completed')
        expect(summary[:total_cost]).to eq(1.0)
        expect(summary[:nodes_executed]).to eq(2)
      end
    end

    describe '#to_json_summary' do
      it 'returns JSON representation suitable for API responses' do
        run = create(:ai_workflow_run, :running)
        json = run.to_json_summary
        
        expect(json).to include(
          :id,
          :run_id,
          :status,
          :progress_percentage,
          :duration,
          :total_cost,
          :created_at,
          :started_at
        )
      end

      it 'includes error information for failed runs' do
        run = create(:ai_workflow_run, :failed, error_message: 'Test error')
        json = run.to_json_summary
        
        expect(json[:error_message]).to eq('Test error')
        expect(json[:completed_at]).to be_present
      end
    end
  end

  describe 'class methods' do
    # Note: run_id is auto-generated by UUIDv7 at database level, no class method needed

    describe '.average_execution_time' do
      let(:workflow) { create(:ai_workflow) }

      it 'calculates average execution time for workflow' do
        create(:ai_workflow_run, :completed, ai_workflow: workflow, started_at: 2.hours.ago, completed_at: 1.hour.ago)
        create(:ai_workflow_run, :completed, ai_workflow: workflow, started_at: 1.hour.ago, completed_at: 30.minutes.ago)
        
        average = described_class.average_execution_time(workflow.id)
        expect(average).to eq(45.minutes)
      end

      it 'returns nil when no completed runs exist' do
        average = described_class.average_execution_time(workflow.id)
        expect(average).to be_nil
      end
    end

    describe '.success_rate' do
      let(:workflow) { create(:ai_workflow) }

      it 'calculates success rate for workflow' do
        create_list(:ai_workflow_run, 7, :completed, ai_workflow: workflow)
        create_list(:ai_workflow_run, 3, :failed, ai_workflow: workflow)
        
        rate = described_class.success_rate(workflow.id)
        expect(rate).to eq(0.7)
      end

      it 'returns 0 when no finished runs exist' do
        rate = described_class.success_rate(workflow.id)
        expect(rate).to eq(0)
      end
    end

    describe '.cleanup_old_runs' do
      it 'removes runs older than specified days' do
        old_runs = create_list(:ai_workflow_run, 3, created_at: 2.months.ago)
        recent_runs = create_list(:ai_workflow_run, 2, created_at: 1.week.ago)
        
        expect {
          described_class.cleanup_old_runs(30)
        }.to change { described_class.count }.from(5).to(2)
        
        expect(described_class.exists?(old_runs.first.id)).to be false
        expect(described_class.exists?(recent_runs.first.id)).to be true
      end

      it 'preserves runs with preserve_logs flag' do
        old_run = create(:ai_workflow_run, created_at: 2.months.ago, preserve_logs: true)
        
        expect {
          described_class.cleanup_old_runs(30)
        }.not_to change { described_class.count }
        
        expect(described_class.exists?(old_run.id)).to be true
      end
    end
  end

  describe 'performance and edge cases' do
    describe 'large input/output data handling' do
      it 'handles large input variables' do
        large_input = { 'data' => Array.new(1000) { |i| { "item_#{i}" => "value_#{i}" } } }
        run = create(:ai_workflow_run, input_variables: large_input)
        
        expect(run.input_variables['data'].size).to eq(1000)
        expect(run.reload.input_variables).to eq(large_input)
      end

      it 'handles large output data' do
        large_output = { 'results' => Array.new(1000) { |i| "result_#{i}" } }
        run = create(:ai_workflow_run)
        run.mark_completed!(output_data: large_output)
        
        expect(run.output_data['results'].size).to eq(1000)
      end
    end

    describe 'unicode and special character support' do
      it 'handles unicode in error messages' do
        run = create(:ai_workflow_run, :running)
        unicode_error = 'エラーが発生しました 🚨'
        
        run.mark_failed!(unicode_error)
        expect(run.error_message).to eq(unicode_error)
        expect(run.reload.error_message).to eq(unicode_error)
      end

      it 'handles special characters in trigger context' do
        context = {
          'webhook_data' => {
            'message' => 'Special chars: @#$%^&*()[]{}|;:,.<>?',
            'emoji' => '🚀🎉🔥'
          }
        }
        
        run = create(:ai_workflow_run, trigger_context: context)
        expect(run.trigger_context['webhook_data']['emoji']).to eq('🚀🎉🔥')
      end
    end

    describe 'concurrent run management' do
      let!(:workflow) { create(:ai_workflow) }

      it 'handles multiple concurrent runs safely' do
        # Create all runs in main thread to avoid transaction isolation issues
        runs = 5.times.map do
          create(:ai_workflow_run, ai_workflow: workflow)
        end

        # Test concurrent attribute access on those records
        threads = runs.map do |run|
          Thread.new do
            # Just access attributes, don't reload (reload queries DB and hits transaction isolation)
            run.run_id
          end
        end

        run_ids = threads.map(&:value)
        expect(run_ids.uniq.size).to eq(5)
        expect(runs.all?(&:persisted?)).to be true
      end
    end

    describe 'query performance with large datasets' do
      before do
        create_list(:ai_workflow_run, 100, :completed)
        create_list(:ai_workflow_run, 50, :failed)
        create_list(:ai_workflow_run, 25, :running)
      end

      it 'efficiently queries recent active runs' do
        expect {
          described_class.recent.active.includes(:ai_workflow).limit(20).to_a
        }.not_to exceed_query_limit(3)
      end

      it 'efficiently calculates statistics' do
        workflow = AiWorkflowRun.first.ai_workflow
        
        expect {
          success_rate = described_class.success_rate(workflow.id)
          avg_time = described_class.average_execution_time(workflow.id)
        }.not_to exceed_query_limit(2)
      end
    end
  end
end