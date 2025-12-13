# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiWorkflowAnalyticsCacheWarmupJob, type: :job do
  subject { described_class }

  it_behaves_like 'a base job', described_class
  it_behaves_like 'a job with API communication'

  let(:job_instance) { described_class.new }
  let(:current_time) { Time.parse('2024-01-15 10:15:00 UTC') }
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
      expect(described_class.get_sidekiq_options['queue']).to eq('analytics')
    end
  end

  describe 'CACHE_CONFIGURATIONS' do
    it 'defines expected cache keys' do
      expect(described_class::CACHE_CONFIGURATIONS.keys).to include(
        'dashboard_summary',
        'execution_stats_1h',
        'execution_stats_24h',
        'cost_summary_24h',
        'provider_health_summary'
      )
    end

    it 'has TTL for each cache' do
      described_class::CACHE_CONFIGURATIONS.each do |key, config|
        expect(config[:ttl]).to be_a(Integer), "#{key} should have a TTL"
        expect(config[:ttl]).to be > 0, "#{key} TTL should be positive"
      end
    end

    it 'has priority for each cache' do
      described_class::CACHE_CONFIGURATIONS.each do |key, config|
        expect([:high, :medium]).to include(config[:priority]), "#{key} should have valid priority"
      end
    end
  end

  describe '#execute' do
    context 'with all caches needing refresh' do
      before do
        stub_stale_caches
        stub_successful_cache_computation
        allow(api_client_double).to receive(:post).with('admin/ai_workflow_cache_warmup_metrics', anything)
      end

      it 'completes successfully' do
        result = job_instance.execute

        expect(result[:status]).to eq('completed')
      end

      it 'warms all caches' do
        result = job_instance.execute

        expect(result[:caches_warmed].size).to be > 0
      end

      it 'reports no failures' do
        result = job_instance.execute

        expect(result[:caches_failed]).to be_empty
      end

      it 'stores warmup metrics' do
        expect(api_client_double).to receive(:post).with('admin/ai_workflow_cache_warmup_metrics', anything)

        job_instance.execute
      end
    end

    context 'with some caches still valid' do
      before do
        stub_mixed_cache_status
        stub_successful_cache_computation
        allow(api_client_double).to receive(:post).with('admin/ai_workflow_cache_warmup_metrics', anything)
      end

      it 'skips valid caches' do
        result = job_instance.execute

        expect(result[:caches_skipped].size).to be > 0
      end
    end

    context 'with cache computation failures' do
      before do
        stub_stale_caches
        stub_partial_cache_failure
        allow(api_client_double).to receive(:post).with('admin/ai_workflow_cache_warmup_metrics', anything)
      end

      it 'returns completed_with_errors status' do
        result = job_instance.execute

        expect(result[:status]).to eq('completed_with_errors')
      end

      it 'tracks failed caches' do
        result = job_instance.execute

        expect(result[:caches_failed].size).to be > 0
      end
    end

    context 'when API fails completely' do
      before do
        allow(api_client_double).to receive(:get).and_raise(StandardError.new('API Error'))
        allow(api_client_double).to receive(:post).and_raise(StandardError.new('API Error'))
      end

      it 'handles errors gracefully' do
        result = job_instance.execute

        # cache_needs_refresh? catches get errors and returns true (retry)
        # Then warm_cache catches post errors and adds to caches_failed
        # So the job completes but with all caches failed
        expect(result[:caches_failed].size).to eq(described_class::CACHE_CONFIGURATIONS.size)
        expect(result[:status]).to eq('completed_with_errors')
      end
    end
  end

  describe 'cache priority' do
    before do
      stub_stale_caches
      stub_successful_cache_computation
      allow(api_client_double).to receive(:post).with('admin/ai_workflow_cache_warmup_metrics', anything)
    end

    it 'processes high priority caches first' do
      call_order = []

      allow(api_client_double).to receive(:post).with('admin/analytics_cache/compute', anything) do |_, args|
        call_order << args[:cache_key]
        { 'success' => true, 'record_count' => 10 }
      end

      job_instance.execute

      # High priority caches should come before medium priority
      high_priority_keys = described_class::CACHE_CONFIGURATIONS
        .select { |_, c| c[:priority] == :high }
        .keys

      first_high_priority_index = call_order.index { |k| high_priority_keys.include?(k) }
      expect(first_high_priority_index).to eq(0)
    end
  end

  private

  def stub_stale_caches
    allow(api_client_double).to receive(:get).with('admin/analytics_cache/status', anything).and_return({
      'exists' => true,
      'stale' => true,
      'expires_in' => 0
    })
  end

  def stub_mixed_cache_status
    call_count = 0
    allow(api_client_double).to receive(:get).with('admin/analytics_cache/status', anything) do
      call_count += 1
      if call_count <= 3
        { 'exists' => true, 'stale' => false, 'expires_in' => 1800 }
      else
        { 'exists' => true, 'stale' => true, 'expires_in' => 0 }
      end
    end
  end

  def stub_successful_cache_computation
    allow(api_client_double).to receive(:post).with('admin/analytics_cache/compute', anything).and_return({
      'success' => true,
      'record_count' => 100
    })
  end

  def stub_partial_cache_failure
    call_count = 0
    allow(api_client_double).to receive(:post).with('admin/analytics_cache/compute', anything) do
      call_count += 1
      if call_count <= 5
        { 'success' => true, 'record_count' => 100 }
      else
        { 'success' => false, 'error' => 'Computation failed' }
      end
    end
  end
end
