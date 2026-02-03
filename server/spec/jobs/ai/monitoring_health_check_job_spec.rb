# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::MonitoringHealthCheckJob, type: :job do
  let(:account) { create(:account) }

  describe '#perform' do
    context 'when account exists' do
      it 'returns true for healthy status' do
        allow_any_instance_of(Ai::MonitoringHealthService)
          .to receive(:comprehensive_health_check)
          .and_return({
            status: 'healthy',
            health_score: 100,
            timestamp: Time.current.iso8601,
            database: { status: 'healthy' },
            redis: { status: 'healthy' },
            providers: { total_providers: 1, healthy_providers: 1, providers: [] },
            workers: { status: 'healthy' }
          })

        result = described_class.new.perform(account.id)
        expect(result).to be true
      end

      it 'returns false for unhealthy status' do
        allow_any_instance_of(Ai::MonitoringHealthService)
          .to receive(:comprehensive_health_check)
          .and_return({
            status: 'unhealthy',
            health_score: 30,
            timestamp: Time.current.iso8601,
            database: { status: 'healthy' },
            redis: { status: 'unhealthy', error: 'Connection refused' },
            providers: { total_providers: 1, healthy_providers: 0, providers: [] },
            workers: { status: 'degraded' }
          })

        result = described_class.new.perform(account.id)
        expect(result).to be false
      end

      it 'stores health snapshot in Redis' do
        redis = instance_double(Redis)
        allow(Redis).to receive(:new).and_return(redis)
        allow(redis).to receive(:setex)
        allow(redis).to receive(:lpush)
        allow(redis).to receive(:ltrim)
        allow(redis).to receive(:expire)

        allow_any_instance_of(Ai::MonitoringHealthService)
          .to receive(:comprehensive_health_check)
          .and_return({
            status: 'healthy',
            health_score: 100,
            timestamp: Time.current.iso8601,
            database: { status: 'healthy' },
            redis: { status: 'healthy' },
            providers: { total_providers: 0, healthy_providers: 0, providers: [] },
            workers: { status: 'healthy' }
          })

        described_class.new.perform(account.id)

        expect(redis).to have_received(:setex).with(
          "ai:health:snapshot:#{account.id}",
          anything,
          anything
        )
      end
    end

    context 'when account does not exist' do
      it 'returns false and logs warning' do
        result = described_class.new.perform('non-existent-id')
        expect(result).to be false
      end
    end

    context 'when health check fails with exception' do
      it 'returns false and handles error gracefully' do
        allow_any_instance_of(Ai::MonitoringHealthService)
          .to receive(:comprehensive_health_check)
          .and_raise(StandardError.new('Unexpected error'))

        # Mock Redis to avoid real connection
        redis = instance_double(Redis)
        allow(Redis).to receive(:new).and_return(redis)
        allow(redis).to receive(:setex)

        result = described_class.new.perform(account.id)
        expect(result).to be false
      end
    end

    context 'alert triggering' do
      it 'triggers alerts for degraded status' do
        allow_any_instance_of(Ai::MonitoringHealthService)
          .to receive(:comprehensive_health_check)
          .and_return({
            status: 'degraded',
            health_score: 60,
            timestamp: Time.current.iso8601,
            database: { status: 'healthy' },
            redis: { status: 'healthy' },
            providers: { total_providers: 2, healthy_providers: 1, providers: [
              { name: 'OpenAI', is_healthy: true },
              { name: 'Anthropic', is_healthy: false }
            ] },
            workers: { status: 'healthy', estimated_backlog: 0 }
          })

        # Mock Redis
        redis = instance_double(Redis)
        allow(Redis).to receive(:new).and_return(redis)
        allow(redis).to receive(:setex)
        allow(redis).to receive(:lpush)
        allow(redis).to receive(:ltrim)
        allow(redis).to receive(:expire)

        expect(Rails.logger).to receive(:warn).with(/AI System Health Alert/)

        described_class.new.perform(account.id)
      end

      it 'triggers critical alerts for critical status' do
        allow_any_instance_of(Ai::MonitoringHealthService)
          .to receive(:comprehensive_health_check)
          .and_return({
            status: 'critical',
            health_score: 10,
            timestamp: Time.current.iso8601,
            database: { status: 'unhealthy', error: 'Connection lost' },
            redis: { status: 'unhealthy', error: 'Connection refused' },
            providers: { total_providers: 0, healthy_providers: 0, providers: [] },
            workers: { status: 'degraded', estimated_backlog: 50 }
          })

        # Mock Redis
        redis = instance_double(Redis)
        allow(Redis).to receive(:new).and_return(redis)
        allow(redis).to receive(:setex)
        allow(redis).to receive(:lpush)
        allow(redis).to receive(:ltrim)
        allow(redis).to receive(:expire)

        expect(Rails.logger).to receive(:error).with(/AI System Health Alert/)

        described_class.new.perform(account.id)
      end
    end
  end

  describe 'job configuration' do
    it 'is queued in the monitoring queue' do
      expect(described_class.new.queue_name).to eq('monitoring')
    end
  end
end
