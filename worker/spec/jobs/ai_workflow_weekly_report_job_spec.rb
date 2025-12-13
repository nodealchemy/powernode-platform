# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiWorkflowWeeklyReportJob, type: :job do
  subject { described_class }

  it_behaves_like 'a base job', described_class
  it_behaves_like 'a job with API communication'

  let(:job_instance) { described_class.new }
  let(:current_time) { Time.parse('2024-01-14 06:00:00 UTC') } # Sunday
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
      expect(described_class.get_sidekiq_options['queue']).to eq('reports')
    end
  end

  describe '#execute' do
    context 'with successful report generation' do
      before do
        stub_successful_report_data
        allow(api_client_double).to receive(:post).with('admin/ai_workflow_reports', anything)
        allow(api_client_double).to receive(:post).with('admin/notifications/broadcast', anything)
      end

      it 'completes successfully' do
        result = job_instance.execute

        expect(result[:status]).to eq('completed')
      end

      it 'includes correct period information' do
        result = job_instance.execute

        expect(result[:period][:week_number]).to eq(Date.current.cweek)
        expect(result[:period][:year]).to eq(Date.current.year)
      end

      it 'generates all report sections' do
        result = job_instance.execute

        expect(result[:sections]).to have_key(:execution_summary)
        expect(result[:sections]).to have_key(:performance_metrics)
        expect(result[:sections]).to have_key(:cost_analysis)
        expect(result[:sections]).to have_key(:provider_usage)
        expect(result[:sections]).to have_key(:error_analysis)
        expect(result[:sections]).to have_key(:top_workflows)
        expect(result[:sections]).to have_key(:trends)
        expect(result[:sections]).to have_key(:recommendations)
      end

      it 'stores the report' do
        expect(api_client_double).to receive(:post).with('admin/ai_workflow_reports', hash_including(
          report_type: 'weekly'
        ))

        job_instance.execute
      end

      it 'distributes notification' do
        expect(api_client_double).to receive(:post).with('admin/notifications/broadcast', hash_including(
          notification_type: 'weekly_report_ready'
        ))

        job_instance.execute
      end
    end

    context 'with execution summary data' do
      before do
        stub_successful_report_data
        allow(api_client_double).to receive(:post)
      end

      it 'calculates success rate' do
        result = job_instance.execute

        expect(result[:sections][:execution_summary][:success_rate]).to be_a(Numeric)
      end
    end

    context 'with cost analysis' do
      before do
        stub_successful_report_data
        allow(api_client_double).to receive(:post)
      end

      it 'calculates week-over-week change' do
        result = job_instance.execute

        expect(result[:sections][:cost_analysis]).to have_key(:week_over_week_change)
      end

      it 'projects monthly cost' do
        result = job_instance.execute

        expect(result[:sections][:cost_analysis]).to have_key(:projected_monthly_cost)
      end
    end

    context 'with recommendations' do
      before do
        stub_report_data_with_issues
        allow(api_client_double).to receive(:post)
      end

      it 'generates recommendations for high error rates' do
        result = job_instance.execute

        error_rec = result[:sections][:recommendations].find { |r| r[:type] == 'error_reduction' }
        expect(error_rec).not_to be_nil
      end
    end

    context 'when API fails' do
      before do
        allow(api_client_double).to receive(:get).and_raise(StandardError.new('API Error'))
        allow(api_client_double).to receive(:post)
      end

      it 'handles errors gracefully' do
        result = job_instance.execute

        # Each generate_* method catches errors internally and returns { error: ... }
        # The job continues and completes, but sections will have errors
        expect(result[:sections][:execution_summary]).to have_key(:error)
      end
    end
  end

  private

  def stub_successful_report_data
    allow(api_client_double).to receive(:get).with('admin/ai_workflows/execution_stats', anything).and_return({
      'total_executions' => 1000,
      'successful_executions' => 950,
      'failed_executions' => 50,
      'cancelled_executions' => 0,
      'unique_workflows' => 25,
      'unique_users' => 10
    })

    allow(api_client_double).to receive(:get).with('admin/ai_workflows/performance_stats', anything).and_return({
      'average_execution_time_ms' => 5000,
      'median_execution_time_ms' => 3000,
      'p95_execution_time_ms' => 15000,
      'p99_execution_time_ms' => 30000,
      'average_nodes_per_workflow' => 5,
      'average_tokens_per_execution' => 2000,
      'total_tokens_used' => 2000000
    })

    allow(api_client_double).to receive(:get).with('admin/ai_workflows/cost_summary', anything).and_return({
      'total_cost' => 500.0,
      'token_cost' => 400.0,
      'api_call_cost' => 100.0,
      'average_cost_per_execution' => 0.5
    })

    allow(api_client_double).to receive(:get).with('admin/ai_workflows/cost_by_provider', anything).and_return({
      'providers' => [
        { 'name' => 'openai', 'total_cost' => 400.0, 'api_calls' => 800, 'token_count' => 1500000 },
        { 'name' => 'anthropic', 'total_cost' => 100.0, 'api_calls' => 200, 'token_count' => 500000 }
      ]
    })

    allow(api_client_double).to receive(:get).with('admin/ai_workflows/error_stats', anything).and_return({
      'total_errors' => 50,
      'error_rate' => 5.0,
      'errors_by_type' => [{ 'type' => 'timeout', 'count' => 30 }],
      'most_common_errors' => ['Timeout', 'Rate limit'],
      'recovered_executions' => 20,
      'recovery_rate' => 40.0
    })

    allow(api_client_double).to receive(:get).with('admin/ai_workflows/top_workflows', anything).and_return({
      'workflows' => [
        { 'name' => 'data_processor', 'execution_count' => 300, 'total_cost' => 150.0, 'success_rate' => 98 },
        { 'name' => 'report_generator', 'execution_count' => 200, 'total_cost' => 100.0, 'success_rate' => 95 }
      ]
    })

    allow(api_client_double).to receive(:get).with('admin/ai_workflows/trends', anything).and_return({
      'execution_trend' => 'increasing',
      'cost_trend' => 'stable',
      'performance_trend' => 'improving',
      'error_rate_trend' => 'decreasing'
    })
  end

  def stub_report_data_with_issues
    stub_successful_report_data

    # Override error stats with high error rate
    allow(api_client_double).to receive(:get).with('admin/ai_workflows/error_stats', anything).and_return({
      'total_errors' => 150,
      'error_rate' => 15.0,  # Above 10% threshold
      'errors_by_type' => [{ 'type' => 'timeout', 'count' => 100 }],
      'most_common_errors' => ['Timeout', 'Rate limit', 'API Error'],
      'recovered_executions' => 20,
      'recovery_rate' => 13.3
    })
  end
end
