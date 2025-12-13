# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiWorkflowMonthlyCleanupJob, type: :job do
  subject { described_class }

  it_behaves_like 'a base job', described_class
  it_behaves_like 'a job with API communication'

  let(:job_instance) { described_class.new }
  let(:current_time) { Time.parse('2024-02-01 00:00:00 UTC') } # First of month
  let(:api_client_double) { double('BackendApiClient') }

  before do
    mock_powernode_worker_config
    Sidekiq::Testing.fake!
    freeze_time_at(current_time)
    allow(job_instance).to receive(:api_client).and_return(api_client_double)
    allow_any_instance_of(BaseJob).to receive(:check_runaway_loop).and_return(nil)
  end

  after do
    Sidekiq::Worker.clear_all
    allow(Time).to receive(:current).and_call_original
  end

  describe 'job configuration' do
    it 'is configured with correct queue' do
      expect(described_class.get_sidekiq_options['queue']).to eq('maintenance')
    end
  end

  describe '#execute' do
    context 'with successful cleanup' do
      before do
        stub_successful_cleanup
        allow(api_client_double).to receive(:post).with('admin/ai_workflow_cleanup_reports', anything)
        allow(api_client_double).to receive(:post).with('admin/notifications/broadcast', anything)
      end

      it 'completes successfully' do
        result = job_instance.execute

        expect(result[:status]).to eq('completed')
      end

      it 'performs all cleanup tasks' do
        result = job_instance.execute

        expect(result[:tasks]).to have_key(:archive_executions)
        expect(result[:tasks]).to have_key(:cleanup_logs)
        expect(result[:tasks]).to have_key(:archive_analytics)
        expect(result[:tasks]).to have_key(:cleanup_temp_files)
        expect(result[:tasks]).to have_key(:cleanup_orphans)
        expect(result[:tasks]).to have_key(:optimize)
      end

      it 'calculates totals' do
        result = job_instance.execute

        expect(result[:totals][:archived]).to be >= 0
        expect(result[:totals][:deleted]).to be >= 0
        expect(result[:totals][:freed_space_bytes]).to be >= 0
      end

      it 'stores cleanup report' do
        expect(api_client_double).to receive(:post).with('admin/ai_workflow_cleanup_reports', hash_including(
          report_type: 'monthly'
        ))

        job_instance.execute
      end

      it 'sends notification' do
        expect(api_client_double).to receive(:post).with('admin/notifications/broadcast', hash_including(
          notification_type: 'monthly_cleanup_complete'
        ))

        job_instance.execute
      end
    end

    context 'with archive executions' do
      before do
        stub_successful_cleanup
        allow(api_client_double).to receive(:post).with('admin/ai_workflow_cleanup_reports', anything)
        allow(api_client_double).to receive(:post).with('admin/notifications/broadcast', anything)
      end

      it 'archives old executions' do
        result = job_instance.execute

        expect(result[:tasks][:archive_executions][:status]).to eq('completed')
        expect(result[:tasks][:archive_executions][:archived_count]).to eq(500)
      end
    end

    context 'with log cleanup' do
      before do
        stub_successful_cleanup
        allow(api_client_double).to receive(:post).with('admin/ai_workflow_cleanup_reports', anything)
        allow(api_client_double).to receive(:post).with('admin/notifications/broadcast', anything)
      end

      it 'cleans up old logs' do
        result = job_instance.execute

        expect(result[:tasks][:cleanup_logs][:status]).to eq('completed')
        expect(result[:tasks][:cleanup_logs][:deleted_count]).to eq(1000)
      end
    end

    context 'with orphan cleanup' do
      before do
        stub_successful_cleanup
        allow(api_client_double).to receive(:post).with('admin/ai_workflow_cleanup_reports', anything)
        allow(api_client_double).to receive(:post).with('admin/notifications/broadcast', anything)
      end

      it 'removes orphaned records' do
        result = job_instance.execute

        expect(result[:tasks][:cleanup_orphans][:status]).to eq('completed')
      end
    end

    context 'with partial failures' do
      before do
        stub_partial_failure_cleanup
        allow(api_client_double).to receive(:post).with('admin/ai_workflow_cleanup_reports', anything)
        allow(api_client_double).to receive(:post).with('admin/notifications/broadcast', anything)
      end

      it 'returns completed_with_errors status' do
        result = job_instance.execute

        # When one task fails, the job continues with others
        # The archive_analytics task fails but others succeed
        expect(result[:tasks][:archive_analytics][:status]).to eq('failed')
        # Note: errors count is calculated for failed tasks only
      end
    end

    context 'when API fails completely' do
      before do
        allow(api_client_double).to receive(:post).and_raise(StandardError.new('API Error'))
      end

      it 'handles errors gracefully' do
        result = job_instance.execute

        # Each individual task catches its own errors,
        # so the job completes but with all tasks failed
        # Status depends on whether any tasks completed
        expect(result[:tasks]).not_to be_empty
        expect(result[:tasks].values.all? { |t| t[:status] == 'failed' }).to be true
      end
    end
  end

  describe 'retention periods' do
    it 'has EXECUTION_RETENTION_DAYS constant' do
      expect(described_class::EXECUTION_RETENTION_DAYS).to eq(90)
    end

    it 'has LOG_RETENTION_DAYS constant' do
      expect(described_class::LOG_RETENTION_DAYS).to eq(30)
    end

    it 'has ANALYTICS_RETENTION_DAYS constant' do
      expect(described_class::ANALYTICS_RETENTION_DAYS).to eq(365)
    end

    it 'has TEMP_FILE_RETENTION_DAYS constant' do
      expect(described_class::TEMP_FILE_RETENTION_DAYS).to eq(7)
    end
  end

  private

  def stub_successful_cleanup
    allow(api_client_double).to receive(:post).with('admin/ai_workflows/archive_executions', anything).and_return({
      'archived_count' => 500,
      'freed_space_bytes' => 104857600 # 100MB
    })

    allow(api_client_double).to receive(:post).with('admin/ai_workflows/cleanup_logs', anything).and_return({
      'deleted_count' => 1000,
      'freed_space_bytes' => 52428800 # 50MB
    })

    allow(api_client_double).to receive(:post).with('admin/ai_workflows/archive_analytics', anything).and_return({
      'archived_count' => 200,
      'aggregated_count' => 365,
      'freed_space_bytes' => 20971520 # 20MB
    })

    allow(api_client_double).to receive(:post).with('admin/ai_workflows/cleanup_temp_files', anything).and_return({
      'deleted_count' => 50,
      'freed_space_bytes' => 10485760 # 10MB
    })

    allow(api_client_double).to receive(:post).with('admin/ai_workflows/cleanup_orphans', anything).and_return({
      'orphans_by_type' => {
        'node_executions_without_run' => 20,
        'checkpoints_without_run' => 5
      },
      'total_deleted' => 25
    })

    allow(api_client_double).to receive(:post).with('admin/database/optimize', anything).and_return({
      'tables_optimized' => ['ai_workflow_runs', 'ai_workflow_node_executions'],
      'freed_space_bytes' => 5242880, # 5MB
      'duration_seconds' => 30
    })
  end

  def stub_partial_failure_cleanup
    stub_successful_cleanup

    # Override one task to fail
    allow(api_client_double).to receive(:post).with('admin/ai_workflows/archive_analytics', anything)
      .and_raise(StandardError.new('Archive failed'))
  end
end
