# frozen_string_literal: true

require 'rails_helper'

# Stub AiWorkflowMonitoringChannel for worker tests
class AiWorkflowMonitoringChannel
  class << self
    attr_accessor :cost_broadcasts

    def broadcast_cost_status(data)
      @cost_broadcasts ||= []
      @cost_broadcasts << data
    end

    def reset_cost!
      @cost_broadcasts = []
    end
  end
end

RSpec.describe AiWorkflowCostMonitoringJob, type: :job do
  subject { described_class }

  it_behaves_like 'a base job', described_class
  it_behaves_like 'a job with API communication'

  let(:job_instance) { described_class.new }
  let(:current_time) { Time.parse('2024-01-15 10:00:00 UTC') }
  let(:api_client_double) { double('BackendApiClient') }

  before do
    mock_powernode_worker_config
    Sidekiq::Testing.fake!
    freeze_time_at(current_time)
    allow(job_instance).to receive(:api_client).and_return(api_client_double)
    AiWorkflowMonitoringChannel.reset_cost! if AiWorkflowMonitoringChannel.respond_to?(:reset_cost!)
    allow_any_instance_of(BaseJob).to receive(:check_runaway_loop).and_return(nil)
  end

  after do
    Sidekiq::Worker.clear_all
    allow(Time).to receive(:current).and_call_original
  end

  describe 'job configuration' do
    it 'is configured with correct queue' do
      expect(described_class.get_sidekiq_options['queue']).to eq('ai_workflow_health')
    end
  end

  describe '#execute' do
    context 'with costs under threshold' do
      before do
        stub_healthy_cost_responses
        allow(api_client_double).to receive(:post).with('admin/ai_workflow_cost_metrics', anything)
      end

      it 'completes successfully with healthy status' do
        result = job_instance.execute

        expect(result[:status]).to eq('healthy')
        expect(result[:alerts]).to be_empty
      end

      it 'includes hourly and daily metrics' do
        result = job_instance.execute

        expect(result[:metrics]).to have_key(:hourly)
        expect(result[:metrics]).to have_key(:daily)
        expect(result[:metrics][:hourly][:total_cost]).to eq(10.0)
        expect(result[:metrics][:daily][:total_cost]).to eq(100.0)
      end

      it 'calculates projections' do
        result = job_instance.execute

        expect(result[:metrics]).to have_key(:projected_monthly_cost)
        expect(result[:metrics]).to have_key(:projected_weekly_cost)
      end
    end

    context 'with costs exceeding warning threshold' do
      before do
        stub_warning_cost_responses
        allow(api_client_double).to receive(:post).with('admin/ai_workflow_cost_metrics', anything)
        allow(api_client_double).to receive(:post).with('admin/system_alerts', anything)
      end

      it 'returns warning status' do
        result = job_instance.execute

        expect(result[:status]).to eq('warning')
      end

      it 'includes cost alerts' do
        result = job_instance.execute

        expect(result[:alerts]).not_to be_empty
        expect(result[:alerts].first[:severity]).to eq('warning')
      end
    end

    context 'with costs exceeding critical threshold' do
      before do
        stub_critical_cost_responses
        allow(api_client_double).to receive(:post).with('admin/ai_workflow_cost_metrics', anything)
        allow(api_client_double).to receive(:post).with('admin/system_alerts', anything)
      end

      it 'returns critical status' do
        result = job_instance.execute

        expect(result[:status]).to eq('critical')
      end

      it 'sends critical alerts' do
        expect(api_client_double).to receive(:post).with('admin/system_alerts', hash_including(severity: 'critical'))

        job_instance.execute
      end
    end

    context 'with cost spike detected' do
      before do
        stub_cost_spike_responses
        allow(api_client_double).to receive(:post).with('admin/ai_workflow_cost_metrics', anything)
        allow(api_client_double).to receive(:post).with('admin/system_alerts', anything)
      end

      it 'detects cost spike' do
        result = job_instance.execute

        spike_alert = result[:alerts].find { |a| a[:type] == 'cost_spike' }
        expect(spike_alert).not_to be_nil
        expect(spike_alert[:severity]).to eq('warning')
      end
    end

    context 'when API fails' do
      before do
        # Stub to raise on the first call, which happens outside any rescue block
        call_count = 0
        allow(api_client_double).to receive(:get) do
          call_count += 1
          raise StandardError.new('API Error')
        end
        allow(api_client_double).to receive(:post)
      end

      it 'handles errors gracefully' do
        result = job_instance.execute

        # The job catches errors in each fetch method, so it continues
        # but the metrics will have errors
        expect(result[:metrics][:hourly]).to have_key(:error)
      end
    end
  end

  private

  def stub_healthy_cost_responses
    allow(api_client_double).to receive(:get).with('admin/ai_workflows/cost_summary', hash_including(period: '1h')).and_return({
      'total_cost' => 10.0,
      'token_cost' => 8.0,
      'api_call_cost' => 2.0,
      'execution_count' => 50,
      'average_cost_per_execution' => 0.2
    })

    allow(api_client_double).to receive(:get).with('admin/ai_workflows/cost_summary', hash_including(period: '24h')).and_return({
      'total_cost' => 100.0,
      'token_cost' => 80.0,
      'api_call_cost' => 20.0,
      'execution_count' => 500,
      'average_cost_per_execution' => 0.2
    })

    allow(api_client_double).to receive(:get).with('admin/ai_workflows/cost_summary', hash_including(start_date: anything)).and_return({
      'total_cost' => 95.0
    })

    allow(api_client_double).to receive(:get).with('admin/ai_workflows/cost_by_provider', anything).and_return({
      'providers' => [
        { 'name' => 'openai', 'total_cost' => 80.0, 'token_count' => 100000 },
        { 'name' => 'anthropic', 'total_cost' => 20.0, 'token_count' => 25000 }
      ]
    })
  end

  def stub_warning_cost_responses
    allow(api_client_double).to receive(:get).with('admin/ai_workflows/cost_summary', hash_including(period: '1h')).and_return({
      'total_cost' => 60.0  # Above $50 warning threshold
    })

    allow(api_client_double).to receive(:get).with('admin/ai_workflows/cost_summary', hash_including(period: '24h')).and_return({
      'total_cost' => 400.0
    })

    allow(api_client_double).to receive(:get).with('admin/ai_workflows/cost_summary', hash_including(start_date: anything)).and_return({
      'total_cost' => 350.0
    })

    allow(api_client_double).to receive(:get).with('admin/ai_workflows/cost_by_provider', anything).and_return({
      'providers' => []
    })
  end

  def stub_critical_cost_responses
    allow(api_client_double).to receive(:get).with('admin/ai_workflows/cost_summary', hash_including(period: '1h')).and_return({
      'total_cost' => 150.0  # Above $100 critical threshold
    })

    allow(api_client_double).to receive(:get).with('admin/ai_workflows/cost_summary', hash_including(period: '24h')).and_return({
      'total_cost' => 1200.0  # Above $1000 critical threshold
    })

    allow(api_client_double).to receive(:get).with('admin/ai_workflows/cost_summary', hash_including(start_date: anything)).and_return({
      'total_cost' => 500.0
    })

    allow(api_client_double).to receive(:get).with('admin/ai_workflows/cost_by_provider', anything).and_return({
      'providers' => []
    })
  end

  def stub_cost_spike_responses
    allow(api_client_double).to receive(:get).with('admin/ai_workflows/cost_summary', hash_including(period: '1h')).and_return({
      'total_cost' => 20.0
    })

    allow(api_client_double).to receive(:get).with('admin/ai_workflows/cost_summary', hash_including(period: '24h')).and_return({
      'total_cost' => 300.0  # Current day cost
    })

    allow(api_client_double).to receive(:get).with('admin/ai_workflows/cost_summary', hash_including(start_date: anything)).and_return({
      'total_cost' => 100.0  # Previous day - 200% increase
    })

    allow(api_client_double).to receive(:get).with('admin/ai_workflows/cost_by_provider', anything).and_return({
      'providers' => []
    })
  end
end
