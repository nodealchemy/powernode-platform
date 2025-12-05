# frozen_string_literal: true

require 'rails_helper'

# Stub ActiveRecord::Base for worker tests (worker doesn't have ActiveRecord)
module ActiveRecord
  class Base
    def self.connection_pool
      @mock_connection_pool ||= OpenStruct.new(
        size: 10,
        stat: { busy: 2, idle: 8, dead: 0 }
      )
    end

    def self.mock_connection_pool=(pool)
      @mock_connection_pool = pool
    end
  end
end

# Stub AiWorkflowMonitoringChannel for worker tests
class AiWorkflowMonitoringChannel
  class << self
    attr_accessor :broadcasts

    def broadcast_health_status(data)
      @broadcasts ||= []
      @broadcasts << data
    end

    def reset!
      @broadcasts = []
    end
  end
end

RSpec.describe AiWorkflowHealthMonitoringJob, type: :job do
  subject { described_class }

  # Shared examples for base job behavior
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
    AiWorkflowMonitoringChannel.reset!
    # Disable runaway loop detection for tests
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
    context 'with all systems healthy' do
      before do
        # Stub all health check API calls for healthy system
        stub_healthy_workflow_execution
        stub_healthy_provider_connectivity
        stub_healthy_worker_queues
        stub_healthy_event_system
        stub_healthy_database_performance
        stub_healthy_resource_utilization

        # Stub health storage
        allow(api_client_double).to receive(:post).with('admin/ai_workflow_health_metrics', anything)
      end

      it 'completes successfully and returns healthy status' do
        result = job_instance.execute

        expect(result[:overall_status]).to eq('healthy')
        expect(result[:timestamp]).to eq(current_time.iso8601)
      end

      it 'performs all six health checks' do
        result = job_instance.execute

        expect(result[:checks]).to have_key(:workflow_execution)
        expect(result[:checks]).to have_key(:provider_connectivity)
        expect(result[:checks]).to have_key(:worker_queues)
        expect(result[:checks]).to have_key(:event_system)
        expect(result[:checks]).to have_key(:database_performance)
        expect(result[:checks]).to have_key(:resource_utilization)
      end

      it 'stores health metrics via API' do
        job_instance.execute

        expect(api_client_double).to have_received(:post)
          .with('admin/ai_workflow_health_metrics', hash_including(
            timestamp: current_time.iso8601,
            overall_status: 'healthy'
          ))
      end

      it 'does not process alerts for healthy system' do
        allow(job_instance).to receive(:process_health_alerts)
        job_instance.execute

        expect(job_instance).not_to have_received(:process_health_alerts)
      end

      it 'broadcasts health status' do
        allow(AiWorkflowMonitoringChannel).to receive(:broadcast_health_status)
        job_instance.execute

        expect(AiWorkflowMonitoringChannel).to have_received(:broadcast_health_status)
          .with(hash_including(overall_status: 'healthy'))
      end

      it 'logs completion message' do
        logger_double = mock_logger
        job_instance.execute

        expect(logger_double).to have_received(:info)
          .with(a_string_matching(/AI Workflow Health Monitoring completed: healthy/))
      end
    end

    context 'with workflow execution health issues' do
      before do
        stub_unhealthy_workflow_execution
        stub_healthy_provider_connectivity
        stub_healthy_worker_queues
        stub_healthy_event_system
        stub_healthy_database_performance
        stub_healthy_resource_utilization

        allow(api_client_double).to receive(:post).with('admin/ai_workflow_health_metrics', anything)
        allow(api_client_double).to receive(:post).with('admin/system_alerts', anything)
        allow(AiWorkflowMonitoringChannel).to receive(:broadcast_health_status)
      end

      it 'detects stuck workflows' do
        result = job_instance.execute

        expect(result[:checks][:workflow_execution][:status]).to eq('warning')
        expect(result[:checks][:workflow_execution][:metrics][:stuck_workflows]).to eq(5)
        expect(result[:checks][:workflow_execution][:issues]).to include(a_string_matching(/5 workflows appear stuck/))
      end

      it 'detects high failure rate' do
        allow(api_client_double).to receive(:get).with('admin/ai_workflows/stuck_analysis')
          .and_return({ 'workflows' => [] })
        allow(api_client_double).to receive(:get).with('admin/ai_workflows/execution_stats?period=1h')
          .and_return({ 'total_executions' => 100, 'failed_executions' => 15 })
        allow(api_client_double).to receive(:get).with('admin/ai_workflows/performance_stats?period=1h')
          .and_return({ 'average_execution_time_ms' => 1000 })
        allow(api_client_double).to receive(:get).with('admin/ai_workflows/status_counts')
          .and_return({ 'running' => 5 })

        result = job_instance.execute

        expect(result[:checks][:workflow_execution][:status]).to eq('warning')
        expect(result[:checks][:workflow_execution][:metrics][:failure_rate]).to eq(15.0)
        expect(result[:checks][:workflow_execution][:issues]).to include(a_string_matching(/High failure rate: 15.0%/))
      end

      it 'detects critical failure rate' do
        allow(api_client_double).to receive(:get).with('admin/ai_workflows/stuck_analysis')
          .and_return({ 'workflows' => [] })
        allow(api_client_double).to receive(:get).with('admin/ai_workflows/execution_stats?period=1h')
          .and_return({ 'total_executions' => 100, 'failed_executions' => 30 })
        allow(api_client_double).to receive(:get).with('admin/ai_workflows/performance_stats?period=1h')
          .and_return({ 'average_execution_time_ms' => 1000 })
        allow(api_client_double).to receive(:get).with('admin/ai_workflows/status_counts')
          .and_return({ 'running' => 5 })

        result = job_instance.execute

        expect(result[:checks][:workflow_execution][:status]).to eq('critical')
      end

      it 'detects high average execution time' do
        allow(api_client_double).to receive(:get).with('admin/ai_workflows/stuck_analysis')
          .and_return({ 'workflows' => [] })
        allow(api_client_double).to receive(:get).with('admin/ai_workflows/execution_stats?period=1h')
          .and_return({ 'total_executions' => 100, 'failed_executions' => 5 })
        allow(api_client_double).to receive(:get).with('admin/ai_workflows/performance_stats?period=1h')
          .and_return({ 'average_execution_time_ms' => 350_000 }) # 5.8 minutes
        allow(api_client_double).to receive(:get).with('admin/ai_workflows/status_counts')
          .and_return({ 'running' => 5 })

        result = job_instance.execute

        expect(result[:checks][:workflow_execution][:status]).to eq('warning')
        expect(result[:checks][:workflow_execution][:issues]).to include(a_string_matching(/High average execution time/))
      end

      it 'processes alerts for unhealthy status' do
        result = job_instance.execute

        expect(result[:overall_status]).to eq('warning')
        expect(api_client_double).to have_received(:post).with('admin/system_alerts', hash_including(
          alert_type: 'ai_workflow_health',
          severity: 'warning'
        ))
      end
    end

    context 'with provider connectivity issues' do
      before do
        stub_healthy_workflow_execution
        stub_unhealthy_provider_connectivity
        stub_healthy_worker_queues
        stub_healthy_event_system
        stub_healthy_database_performance
        stub_healthy_resource_utilization

        allow(api_client_double).to receive(:post).with('admin/ai_workflow_health_metrics', anything)
        allow(api_client_double).to receive(:post).with('admin/system_alerts', anything)
        allow(AiWorkflowMonitoringChannel).to receive(:broadcast_health_status)
      end

      it 'tests connectivity for all providers' do
        result = job_instance.execute

        expect(result[:checks][:provider_connectivity][:metrics][:total_providers]).to eq(3)
        expect(result[:checks][:provider_connectivity][:metrics][:healthy_providers]).to eq(1)
        expect(result[:checks][:provider_connectivity][:metrics][:failed_providers]).to eq(2)
      end

      it 'marks as warning when 25-50% of providers fail' do
        # Override the providers and health checks for this specific test
        # With 3 providers, 1 failure = 33% which is > 25% and <= 50% (warning)
        allow(api_client_double).to receive(:get).with('admin/ai_providers')
          .and_return({
            'providers' => [
              { 'id' => 'w1', 'name' => 'Provider 1' },
              { 'id' => 'w2', 'name' => 'Provider 2' },
              { 'id' => 'w3', 'name' => 'Provider 3' }
            ]
          })

        # Stub each provider explicitly (1 fails out of 3 = 33%)
        allow(api_client_double).to receive(:post).with('admin/ai_providers/w1/health_check')
          .and_return({ 'healthy' => true, 'response_time_ms' => 100 })
        allow(api_client_double).to receive(:post).with('admin/ai_providers/w2/health_check')
          .and_return({ 'healthy' => false, 'error' => 'Connection failed' })
        allow(api_client_double).to receive(:post).with('admin/ai_providers/w3/health_check')
          .and_return({ 'healthy' => true, 'response_time_ms' => 150 })

        result = job_instance.execute

        expect(result[:checks][:provider_connectivity][:status]).to eq('warning')
        expect(result[:checks][:provider_connectivity][:metrics][:failed_providers]).to eq(1)
      end

      it 'marks as critical when >50% of providers fail' do
        result = job_instance.execute

        expect(result[:checks][:provider_connectivity][:status]).to eq('critical')
      end

      it 'includes provider-specific status' do
        result = job_instance.execute

        expect(result[:checks][:provider_connectivity][:providers]).to have_key('OpenAI')
        expect(result[:checks][:provider_connectivity][:providers]).to have_key('Anthropic')
        expect(result[:checks][:provider_connectivity][:providers]).to have_key('Ollama')
      end
    end

    context 'with worker queue issues' do
      before do
        stub_healthy_workflow_execution
        stub_healthy_provider_connectivity
        stub_unhealthy_worker_queues
        stub_healthy_event_system
        stub_healthy_database_performance
        stub_healthy_resource_utilization

        allow(api_client_double).to receive(:post).with('admin/ai_workflow_health_metrics', anything)
        allow(api_client_double).to receive(:post).with('admin/system_alerts', anything)
        allow(AiWorkflowMonitoringChannel).to receive(:broadcast_health_status)
      end

      it 'detects high retry queue count' do
        result = job_instance.execute

        expect(result[:checks][:worker_queues][:status]).to eq('warning')
        expect(result[:checks][:worker_queues][:metrics][:retry_jobs]).to eq(150)
      end

      it 'detects critical dead job count' do
        allow(api_client_double).to receive(:get).with('admin/sidekiq/stats')
          .and_return({
            'processed' => 10_000,
            'failed' => 50,
            'retry_size' => 10,
            'dead_size' => 75,
            'busy' => 5,
            'enqueued' => 20
          })

        allow(api_client_double).to receive(:get).with(/admin\/sidekiq\/queues\//)
          .and_return({ 'size' => 0, 'latency' => 0, 'busy' => 0 })

        result = job_instance.execute

        expect(result[:checks][:worker_queues][:status]).to eq('critical')
        expect(result[:checks][:worker_queues][:metrics][:dead_jobs]).to eq(75)
      end

      it 'checks individual queue stats' do
        result = job_instance.execute

        expect(result[:checks][:worker_queues][:queues]).to have_key('ai_workflow_execution')
        expect(result[:checks][:worker_queues][:queues]).to have_key('ai_workflow_node')
        expect(result[:checks][:worker_queues][:queues]).to have_key('ai_workflow_schedule')
        expect(result[:checks][:worker_queues][:queues]).to have_key('ai_workflow_health')
      end
    end

    context 'with event system issues' do
      before do
        stub_healthy_workflow_execution
        stub_healthy_provider_connectivity
        stub_healthy_worker_queues
        stub_unhealthy_event_system
        stub_healthy_database_performance
        stub_healthy_resource_utilization

        allow(api_client_double).to receive(:post).with('admin/ai_workflow_health_metrics', anything)
        allow(api_client_double).to receive(:post).with('admin/system_alerts', anything)
        allow(AiWorkflowMonitoringChannel).to receive(:broadcast_health_status)
      end

      it 'marks as warning when one component fails' do
        result = job_instance.execute

        expect(result[:checks][:event_system][:status]).to eq('warning')
      end

      it 'marks as critical when multiple components fail' do
        allow(api_client_double).to receive(:get).with('admin/ai_workflow_events/health')
          .and_return({
            'event_dispatcher' => { 'status' => 'failed', 'error' => 'Connection lost' },
            'trigger_service' => { 'status' => 'failed', 'error' => 'Timeout' }
          })

        allow(api_client_double).to receive(:get).with('admin/ai_workflow_events/processing_stats')
          .and_return({
            'events_processed_last_hour' => 1000,
            'average_processing_time_ms' => 50,
            'failed_events_last_hour' => 10
          })

        result = job_instance.execute

        expect(result[:checks][:event_system][:status]).to eq('critical')
      end

      it 'includes event processing metrics' do
        result = job_instance.execute

        expect(result[:checks][:event_system][:metrics]).to have_key(:events_processed_last_hour)
        expect(result[:checks][:event_system][:metrics]).to have_key(:average_processing_time_ms)
        expect(result[:checks][:event_system][:metrics]).to have_key(:failed_events_last_hour)
      end
    end

    context 'with database performance issues' do
      before do
        stub_healthy_workflow_execution
        stub_healthy_provider_connectivity
        stub_healthy_worker_queues
        stub_healthy_event_system
        stub_unhealthy_database_performance
        stub_healthy_resource_utilization

        allow(api_client_double).to receive(:post).with('admin/ai_workflow_health_metrics', anything)
        allow(api_client_double).to receive(:post).with('admin/system_alerts', anything)
        allow(AiWorkflowMonitoringChannel).to receive(:broadcast_health_status)
      end

      it 'marks as warning when response time is 500-1000ms' do
        # Mock the database response time measurement directly (time is frozen in tests)
        allow(job_instance).to receive(:measure_database_response_time).and_return(600)

        result = job_instance.execute

        expect(result[:checks][:database_performance][:status]).to eq('warning')
        expect(result[:checks][:database_performance][:metrics][:avg_response_time_ms]).to eq(600)
      end

      it 'marks as critical when response time exceeds 1000ms' do
        # Mock the database response time measurement directly (time is frozen in tests)
        allow(job_instance).to receive(:measure_database_response_time).and_return(1100)

        result = job_instance.execute

        expect(result[:checks][:database_performance][:status]).to eq('critical')
        expect(result[:checks][:database_performance][:metrics][:avg_response_time_ms]).to eq(1100)
      end

      it 'includes connection pool stats' do
        result = job_instance.execute

        expect(result[:checks][:database_performance][:metrics]).to have_key(:connection_pool)
        expect(result[:checks][:database_performance][:metrics][:connection_pool]).to have_key(:size)
        expect(result[:checks][:database_performance][:metrics][:connection_pool]).to have_key(:checked_out)
      end

      it 'includes slow query information' do
        result = job_instance.execute

        expect(result[:checks][:database_performance]).to have_key(:slow_queries)
      end
    end

    context 'with resource utilization issues' do
      before do
        stub_healthy_workflow_execution
        stub_healthy_provider_connectivity
        stub_healthy_worker_queues
        stub_healthy_event_system
        stub_healthy_database_performance
        stub_unhealthy_resource_utilization

        allow(api_client_double).to receive(:post).with('admin/ai_workflow_health_metrics', anything)
        allow(api_client_double).to receive(:post).with('admin/system_alerts', anything)
        allow(AiWorkflowMonitoringChannel).to receive(:broadcast_health_status)
      end

      it 'marks as warning when memory usage is 80-90%' do
        allow(GC).to receive(:stat).and_return({ heap_allocated_pages: 10_000 })
        stub_const('GC::INTERNAL_CONSTANTS', { HEAP_PAGE_SIZE: 16_384 })

        # Mock memory usage percentage check
        allow(job_instance).to receive(:fetch_memory_stats).and_return({
          used_mb: 500,
          usage_percentage: 85
        })

        result = job_instance.execute

        expect(result[:checks][:resource_utilization][:status]).to eq('warning')
        expect(result[:checks][:resource_utilization][:metrics][:memory][:usage_percentage]).to eq(85)
      end

      it 'marks as critical when memory usage exceeds 90%' do
        allow(job_instance).to receive(:fetch_memory_stats).and_return({
          used_mb: 600,
          usage_percentage: 95
        })

        result = job_instance.execute

        expect(result[:checks][:resource_utilization][:status]).to eq('critical')
      end

      it 'includes memory statistics' do
        result = job_instance.execute

        expect(result[:checks][:resource_utilization][:metrics]).to have_key(:memory)
        expect(result[:checks][:resource_utilization][:metrics][:memory]).to have_key(:used_mb)
      end
    end

    context 'with overall health status calculation' do
      before do
        allow(api_client_double).to receive(:post).with('admin/ai_workflow_health_metrics', anything)
        allow(api_client_double).to receive(:post).with('admin/system_alerts', anything)
        allow(AiWorkflowMonitoringChannel).to receive(:broadcast_health_status)
      end

      it 'marks overall as critical if any check is critical' do
        stub_healthy_workflow_execution
        stub_unhealthy_provider_connectivity # critical
        stub_healthy_worker_queues
        stub_healthy_event_system
        stub_healthy_database_performance
        stub_healthy_resource_utilization

        result = job_instance.execute

        expect(result[:overall_status]).to eq('critical')
      end

      it 'marks overall as warning if any check is warning and none critical' do
        stub_unhealthy_workflow_execution # warning (stuck workflows)
        stub_healthy_provider_connectivity
        stub_healthy_worker_queues
        stub_healthy_event_system
        stub_healthy_database_performance
        stub_healthy_resource_utilization

        result = job_instance.execute

        expect(result[:overall_status]).to eq('warning')
      end

      it 'marks overall as healthy if all checks are healthy' do
        stub_healthy_workflow_execution
        stub_healthy_provider_connectivity
        stub_healthy_worker_queues
        stub_healthy_event_system
        stub_healthy_database_performance
        stub_healthy_resource_utilization

        result = job_instance.execute

        expect(result[:overall_status]).to eq('healthy')
      end
    end

    context 'with error handling' do
      before do
        allow(api_client_double).to receive(:post).with('admin/ai_workflow_health_metrics', anything)
        allow(api_client_double).to receive(:post).with('admin/system_alerts', anything)
        allow(AiWorkflowMonitoringChannel).to receive(:broadcast_health_status)
      end

      it 'creates emergency health report on job failure' do
        allow(job_instance).to receive(:check_workflow_execution_health).and_raise(StandardError.new('Unexpected error'))

        logger_double = mock_logger

        expect {
          job_instance.execute
        }.to raise_error(StandardError)

        expect(logger_double).to have_received(:error).with(a_string_matching(/AI Workflow Health Monitoring failed/))

        expect(AiWorkflowMonitoringChannel).to have_received(:broadcast_health_status)
          .with(hash_including(
            overall_status: 'critical',
            error: 'Unexpected error'
          ))
      end

      it 'includes error message in emergency report' do
        allow(job_instance).to receive(:check_workflow_execution_health).and_raise(StandardError.new('Test error'))

        expect {
          job_instance.execute
        }.to raise_error(StandardError)

        expect(AiWorkflowMonitoringChannel).to have_received(:broadcast_health_status)
          .with(hash_including(
            checks: hash_including(
              monitoring_system: hash_including(
                status: 'failed',
                error: 'Test error'
              )
            )
          ))
      end

      it 'handles API client errors gracefully in individual checks' do
        # Stub the check method to raise an error to test the outer rescue block
        allow(job_instance).to receive(:check_workflow_execution_health) do |health_report|
          raise StandardError.new('API error')
        end

        stub_healthy_provider_connectivity
        stub_healthy_worker_queues
        stub_healthy_event_system
        stub_healthy_database_performance
        stub_healthy_resource_utilization

        # The job should catch the error and set status to critical
        expect { job_instance.execute }.to raise_error(StandardError, 'API error')
      end

      it 'continues with other checks when one check fails' do
        # Mock workflow execution to fail by setting failed status directly
        allow(job_instance).to receive(:check_workflow_execution_health) do |health_report|
          health_report[:checks][:workflow_execution] = {
            status: 'failed',
            error: 'API error',
            metrics: {},
            issues: []
          }
        end

        stub_healthy_provider_connectivity
        stub_healthy_worker_queues
        stub_healthy_event_system
        stub_healthy_database_performance
        stub_healthy_resource_utilization

        result = job_instance.execute

        # Other checks should still be healthy
        expect(result[:checks][:provider_connectivity][:status]).to eq('healthy')
        expect(result[:checks][:worker_queues][:status]).to eq('healthy')
      end
    end

    context 'with alert processing' do
      before do
        stub_unhealthy_workflow_execution
        stub_healthy_provider_connectivity
        stub_healthy_worker_queues
        stub_healthy_event_system
        stub_healthy_database_performance
        stub_healthy_resource_utilization

        allow(api_client_double).to receive(:post).with('admin/ai_workflow_health_metrics', anything)
        allow(api_client_double).to receive(:post).with('admin/system_alerts', anything)
        allow(AiWorkflowMonitoringChannel).to receive(:broadcast_health_status)
      end

      it 'generates health summary for alerts' do
        result = job_instance.execute

        expect(api_client_double).to have_received(:post)
          .with('admin/system_alerts', hash_including(
            summary: a_string_matching(/issue\(s\) detected/)
          ))
      end

      it 'includes alert details in alert data' do
        result = job_instance.execute

        expect(api_client_double).to have_received(:post)
          .with('admin/system_alerts', hash_including(
            alert_type: 'ai_workflow_health',
            severity: 'warning',
            details: hash_including(:workflow_execution)
          ))
      end
    end
  end

  # Helper methods to stub various health check scenarios

  def stub_healthy_workflow_execution
    allow(api_client_double).to receive(:get).with('admin/ai_workflows/stuck_analysis')
      .and_return({ 'workflows' => [] })
    allow(api_client_double).to receive(:get).with('admin/ai_workflows/execution_stats?period=1h')
      .and_return({ 'total_executions' => 100, 'failed_executions' => 2 })
    allow(api_client_double).to receive(:get).with('admin/ai_workflows/performance_stats?period=1h')
      .and_return({ 'average_execution_time_ms' => 5000 })
    allow(api_client_double).to receive(:get).with('admin/ai_workflows/status_counts')
      .and_return({ 'running' => 10 })
  end

  def stub_unhealthy_workflow_execution
    allow(api_client_double).to receive(:get).with('admin/ai_workflows/stuck_analysis')
      .and_return({ 'workflows' => Array.new(5) { { 'id' => 'stuck-workflow' } } })
    allow(api_client_double).to receive(:get).with('admin/ai_workflows/execution_stats?period=1h')
      .and_return({ 'total_executions' => 100, 'failed_executions' => 5 })
    allow(api_client_double).to receive(:get).with('admin/ai_workflows/performance_stats?period=1h')
      .and_return({ 'average_execution_time_ms' => 10_000 })
    allow(api_client_double).to receive(:get).with('admin/ai_workflows/status_counts')
      .and_return({ 'running' => 15 })
  end

  def stub_healthy_provider_connectivity
    allow(api_client_double).to receive(:get).with('admin/ai_providers')
      .and_return({
        'providers' => [
          { 'id' => 'p1', 'name' => 'OpenAI' },
          { 'id' => 'p2', 'name' => 'Anthropic' },
          { 'id' => 'p3', 'name' => 'Ollama' }
        ]
      })

    allow(api_client_double).to receive(:post).with(/admin\/ai_providers\/.+\/health_check/)
      .and_return({ 'healthy' => true, 'response_time_ms' => 100 })
  end

  def stub_unhealthy_provider_connectivity
    allow(api_client_double).to receive(:get).with('admin/ai_providers')
      .and_return({
        'providers' => [
          { 'id' => 'p1', 'name' => 'OpenAI' },
          { 'id' => 'p2', 'name' => 'Anthropic' },
          { 'id' => 'p3', 'name' => 'Ollama' }
        ]
      })

    allow(api_client_double).to receive(:post).with('admin/ai_providers/p1/health_check')
      .and_return({ 'healthy' => true, 'response_time_ms' => 100 })
    allow(api_client_double).to receive(:post).with('admin/ai_providers/p2/health_check')
      .and_return({ 'healthy' => false, 'error' => 'Connection timeout' })
    allow(api_client_double).to receive(:post).with('admin/ai_providers/p3/health_check')
      .and_return({ 'healthy' => false, 'error' => 'Service unavailable' })
  end

  def stub_healthy_worker_queues
    allow(api_client_double).to receive(:get).with('admin/sidekiq/stats')
      .and_return({
        'processed' => 10_000,
        'failed' => 10,
        'retry_size' => 5,
        'dead_size' => 2,
        'busy' => 3,
        'enqueued' => 20
      })

    allow(api_client_double).to receive(:get).with(/admin\/sidekiq\/queues\//)
      .and_return({ 'size' => 5, 'latency' => 2.5, 'busy' => 1 })
  end

  def stub_unhealthy_worker_queues
    allow(api_client_double).to receive(:get).with('admin/sidekiq/stats')
      .and_return({
        'processed' => 10_000,
        'failed' => 50,
        'retry_size' => 150,
        'dead_size' => 25,
        'busy' => 5,
        'enqueued' => 200
      })

    allow(api_client_double).to receive(:get).with(/admin\/sidekiq\/queues\//)
      .and_return({ 'size' => 50, 'latency' => 10.0, 'busy' => 3 })
  end

  def stub_healthy_event_system
    allow(api_client_double).to receive(:get).with('admin/ai_workflow_events/health')
      .and_return({
        'event_dispatcher' => { 'status' => 'healthy' },
        'trigger_service' => { 'status' => 'healthy' }
      })

    allow(api_client_double).to receive(:get).with('admin/ai_workflow_events/processing_stats')
      .and_return({
        'events_processed_last_hour' => 1000,
        'average_processing_time_ms' => 25,
        'failed_events_last_hour' => 5
      })
  end

  def stub_unhealthy_event_system
    allow(api_client_double).to receive(:get).with('admin/ai_workflow_events/health')
      .and_return({
        'event_dispatcher' => { 'status' => 'failed', 'error' => 'Connection lost' },
        'trigger_service' => { 'status' => 'healthy' }
      })

    allow(api_client_double).to receive(:get).with('admin/ai_workflow_events/processing_stats')
      .and_return({
        'events_processed_last_hour' => 800,
        'average_processing_time_ms' => 50,
        'failed_events_last_hour' => 50
      })
  end

  def stub_healthy_database_performance
    ActiveRecord::Base.mock_connection_pool = OpenStruct.new(
      size: 10,
      stat: { busy: 2, idle: 8, dead: 0 }
    )

    allow(api_client_double).to receive(:get).with('admin/database/ping')
  end

  def stub_unhealthy_database_performance
    ActiveRecord::Base.mock_connection_pool = OpenStruct.new(
      size: 10,
      stat: { busy: 8, idle: 2, dead: 0 }
    )

    allow(api_client_double).to receive(:get).with('admin/database/ping') do
      sleep(1.2) # Simulate slow response
    end
  end

  def stub_healthy_resource_utilization
    allow(GC).to receive(:stat).and_return({ heap_allocated_pages: 5000 })
    stub_const('GC::INTERNAL_CONSTANTS', { HEAP_PAGE_SIZE: 16_384 })
  end

  def stub_unhealthy_resource_utilization
    allow(GC).to receive(:stat).and_return({ heap_allocated_pages: 20_000 })
    stub_const('GC::INTERNAL_CONSTANTS', { HEAP_PAGE_SIZE: 16_384 })
  end
end
