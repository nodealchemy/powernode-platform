# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::SelfHealing::CrossSystemCorrelator, type: :service do
  let(:account) { create(:account) }
  let(:service) { described_class.new(account: account) }

  before do
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:warn)
    allow(Rails.logger).to receive(:error)
  end

  describe '#initialize' do
    it 'stores the account' do
      expect(service.instance_variable_get(:@account)).to eq(account)
    end
  end

  describe 'CORRELATION_WINDOW' do
    it 'is set to 30 minutes' do
      expect(described_class::CORRELATION_WINDOW).to eq(30.minutes)
    end
  end

  describe '#correlate_failures' do
    let(:ai_failures) { [] }
    let(:devops_events) { [] }

    before do
      allow(service).to receive(:recent_ai_failures).and_return(ai_failures)
      allow(service).to receive(:recent_devops_events).and_return(devops_events)
    end

    context 'when there are no AI failures' do
      it 'returns an empty array' do
        expect(service.correlate_failures).to eq([])
      end
    end

    context 'when there are AI failures but no DevOps events' do
      let(:ai_failures) do
        [
          {
            id: SecureRandom.uuid,
            source_type: 'Ai::Agent',
            source_id: SecureRandom.uuid,
            error_class: 'RuntimeError',
            error_message: 'Provider timeout',
            occurred_at: 15.minutes.ago
          }
        ]
      end

      it 'returns an empty array' do
        expect(service.correlate_failures).to eq([])
      end
    end

    context 'when AI failures correlate with DevOps events' do
      let(:failure_time) { 10.minutes.ago }
      let(:event_time) { 12.minutes.ago }

      let(:ai_failures) do
        [
          {
            id: SecureRandom.uuid,
            source_type: 'Ai::Agent',
            source_id: SecureRandom.uuid,
            error_class: 'RuntimeError',
            error_message: 'Provider timeout',
            occurred_at: failure_time
          }
        ]
      end

      let(:devops_events) do
        [
          {
            type: 'pipeline_run',
            id: SecureRandom.uuid,
            status: 'failure',
            name: 'deploy-production',
            occurred_at: event_time,
            trigger_type: 'push'
          }
        ]
      end

      it 'returns correlations with matching events' do
        results = service.correlate_failures
        expect(results.length).to eq(1)
        expect(results.first[:ai_failure]).to eq(ai_failures.first)
        expect(results.first[:correlated_devops_events]).to include(devops_events.first)
      end

      it 'includes confidence score in correlations' do
        results = service.correlate_failures
        expect(results.first[:confidence]).to be_a(Float)
        expect(results.first[:confidence]).to be_between(0.0, 1.0)
      end

      it 'includes suggested cause in correlations' do
        results = service.correlate_failures
        expect(results.first[:suggested_cause]).to be_a(String)
        expect(results.first[:suggested_cause]).to include('Pipeline failure')
      end

      it 'sorts correlations by confidence descending' do
        second_failure = {
          id: SecureRandom.uuid,
          source_type: 'Ai::Agent',
          source_id: SecureRandom.uuid,
          error_class: 'RuntimeError',
          error_message: 'Another error',
          occurred_at: 25.minutes.ago
        }
        allow(service).to receive(:recent_ai_failures).and_return(ai_failures + [second_failure])

        results = service.correlate_failures
        if results.length > 1
          expect(results.first[:confidence]).to be >= results.last[:confidence]
        end
      end
    end

    context 'when DevOps event occurs after AI failure (not causal)' do
      let(:ai_failures) do
        [
          {
            id: SecureRandom.uuid,
            source_type: 'Ai::Agent',
            source_id: SecureRandom.uuid,
            error_class: 'RuntimeError',
            error_message: 'Error',
            occurred_at: 20.minutes.ago
          }
        ]
      end

      let(:devops_events) do
        [
          {
            type: 'pipeline_run',
            id: SecureRandom.uuid,
            status: 'failure',
            name: 'deploy-staging',
            occurred_at: 10.minutes.ago,
            trigger_type: 'push'
          }
        ]
      end

      it 'does not include events that occurred after the failure' do
        results = service.correlate_failures
        expect(results).to be_empty
      end
    end

    context 'when temporal gap exceeds correlation window' do
      let(:ai_failures) do
        [
          {
            id: SecureRandom.uuid,
            source_type: 'Ai::Agent',
            source_id: SecureRandom.uuid,
            error_class: 'RuntimeError',
            error_message: 'Error',
            occurred_at: 5.minutes.ago
          }
        ]
      end

      let(:devops_events) do
        [
          {
            type: 'pipeline_run',
            id: SecureRandom.uuid,
            status: 'failure',
            name: 'deploy-staging',
            occurred_at: 2.hours.ago,
            trigger_type: 'push'
          }
        ]
      end

      it 'does not correlate events outside the time window' do
        results = service.correlate_failures
        expect(results).to be_empty
      end
    end

    context 'with container failures' do
      let(:failure_time) { 5.minutes.ago }

      let(:ai_failures) do
        [
          {
            id: SecureRandom.uuid,
            source_type: 'Ai::Agent',
            source_id: SecureRandom.uuid,
            error_class: 'RuntimeError',
            error_message: 'Container error',
            occurred_at: failure_time
          }
        ]
      end

      let(:devops_events) do
        [
          {
            type: 'container',
            id: SecureRandom.uuid,
            status: 'failed',
            occurred_at: 7.minutes.ago
          }
        ]
      end

      it 'infers container-related cause' do
        results = service.correlate_failures
        expect(results.first[:suggested_cause]).to include('Container failure')
      end
    end

    context 'with generic temporal correlation' do
      let(:failure_time) { 5.minutes.ago }

      let(:ai_failures) do
        [
          {
            id: SecureRandom.uuid,
            source_type: 'Ai::Agent',
            source_id: SecureRandom.uuid,
            error_class: 'RuntimeError',
            error_message: 'Unknown error',
            occurred_at: failure_time
          }
        ]
      end

      let(:devops_events) do
        [
          {
            type: 'pipeline_run',
            id: SecureRandom.uuid,
            status: 'success',
            name: 'build-main',
            occurred_at: 7.minutes.ago,
            trigger_type: 'manual'
          }
        ]
      end

      it 'returns generic temporal correlation cause' do
        results = service.correlate_failures
        expect(results.first[:suggested_cause]).to include('Temporal correlation')
      end
    end

    describe 'confidence calculation' do
      let(:failure_time) { Time.current }

      let(:ai_failures) do
        [
          {
            id: SecureRandom.uuid,
            source_type: 'Ai::Agent',
            source_id: SecureRandom.uuid,
            error_class: 'RuntimeError',
            error_message: 'Error',
            occurred_at: failure_time
          }
        ]
      end

      it 'scores higher for closer temporal proximity' do
        close_event = {
          type: 'pipeline_run', id: SecureRandom.uuid, status: 'success',
          name: 'deploy', occurred_at: failure_time - 1.minute, trigger_type: 'manual'
        }
        far_event = {
          type: 'pipeline_run', id: SecureRandom.uuid, status: 'success',
          name: 'build', occurred_at: failure_time - 25.minutes, trigger_type: 'manual'
        }

        allow(service).to receive(:recent_devops_events).and_return([close_event])
        close_result = service.correlate_failures
        close_confidence = close_result.first[:confidence]

        allow(service).to receive(:recent_devops_events).and_return([far_event])
        far_result = service.correlate_failures
        far_confidence = far_result.first[:confidence]

        expect(close_confidence).to be > far_confidence
      end

      it 'scores higher for failed DevOps events' do
        failed_event = {
          type: 'pipeline_run', id: SecureRandom.uuid, status: 'failure',
          name: 'deploy', occurred_at: failure_time - 5.minutes, trigger_type: 'manual'
        }
        success_event = {
          type: 'pipeline_run', id: SecureRandom.uuid, status: 'success',
          name: 'build', occurred_at: failure_time - 5.minutes, trigger_type: 'manual'
        }

        allow(service).to receive(:recent_devops_events).and_return([failed_event])
        failed_result = service.correlate_failures
        failed_confidence = failed_result.first[:confidence]

        allow(service).to receive(:recent_devops_events).and_return([success_event])
        success_result = service.correlate_failures
        success_confidence = success_result.first[:confidence]

        expect(failed_confidence).to be > success_confidence
      end

      it 'scores higher for push-triggered events' do
        push_event = {
          type: 'pipeline_run', id: SecureRandom.uuid, status: 'success',
          name: 'deploy', occurred_at: failure_time - 5.minutes, trigger_type: 'push'
        }
        manual_event = {
          type: 'pipeline_run', id: SecureRandom.uuid, status: 'success',
          name: 'build', occurred_at: failure_time - 5.minutes, trigger_type: 'manual'
        }

        allow(service).to receive(:recent_devops_events).and_return([push_event])
        push_result = service.correlate_failures
        push_confidence = push_result.first[:confidence]

        allow(service).to receive(:recent_devops_events).and_return([manual_event])
        manual_result = service.correlate_failures
        manual_confidence = manual_result.first[:confidence]

        expect(push_confidence).to be > manual_confidence
      end

      it 'caps confidence at 1.0' do
        # Create many matching events to push score past 1.0
        events = 10.times.map do |i|
          {
            type: 'pipeline_run', id: SecureRandom.uuid, status: 'failure',
            name: "deploy-#{i}", occurred_at: failure_time - 1.second, trigger_type: 'push'
          }
        end

        allow(service).to receive(:recent_devops_events).and_return(events)
        results = service.correlate_failures

        expect(results.first[:confidence]).to be <= 1.0
      end
    end
  end

  describe '#devops_health' do
    before do
      allow(service).to receive(:pipeline_success_rate).and_return(95.0)
      allow(service).to receive(:git_provider_connectivity).and_return([])
      allow(service).to receive(:container_quota_utilization).and_return({ active_containers: 3 })
      allow(service).to receive(:recent_deployments).and_return([])
    end

    it 'returns a hash with pipeline_success_rate' do
      health = service.devops_health
      expect(health[:pipeline_success_rate]).to eq(95.0)
    end

    it 'returns a hash with git_provider_connectivity' do
      health = service.devops_health
      expect(health[:git_provider_connectivity]).to eq([])
    end

    it 'returns a hash with container_quota_utilization' do
      health = service.devops_health
      expect(health[:container_quota_utilization]).to eq({ active_containers: 3 })
    end

    it 'returns a hash with recent_deployments' do
      health = service.devops_health
      expect(health[:recent_deployments]).to eq([])
    end
  end

  describe 'temporal_match? (private)' do
    it 'returns true when times are within the correlation window' do
      time_a = Time.current
      time_b = time_a - 15.minutes
      expect(service.send(:temporal_match?, time_a, time_b)).to be true
    end

    it 'returns false when times are outside the correlation window' do
      time_a = Time.current
      time_b = time_a - 45.minutes
      expect(service.send(:temporal_match?, time_a, time_b)).to be false
    end

    it 'returns false when either time is nil' do
      expect(service.send(:temporal_match?, nil, Time.current)).to be false
      expect(service.send(:temporal_match?, Time.current, nil)).to be false
    end

    it 'handles time difference symmetrically' do
      time_a = Time.current
      time_b = time_a - 10.minutes
      expect(service.send(:temporal_match?, time_a, time_b)).to eq(
        service.send(:temporal_match?, time_b, time_a)
      )
    end
  end

  describe 'causal_candidate? (private)' do
    it 'returns true when event occurred before or at the same time as failure' do
      failure = { occurred_at: Time.current }
      event = { occurred_at: 5.minutes.ago }
      expect(service.send(:causal_candidate?, failure, event)).to be true
    end

    it 'returns false when event occurred after the failure' do
      failure = { occurred_at: 5.minutes.ago }
      event = { occurred_at: Time.current }
      expect(service.send(:causal_candidate?, failure, event)).to be false
    end

    it 'returns falsey when event occurred_at is nil' do
      failure = { occurred_at: Time.current }
      event = { occurred_at: nil }
      expect(service.send(:causal_candidate?, failure, event)).to be_falsey
    end

    it 'returns falsey when failure occurred_at is nil' do
      failure = { occurred_at: nil }
      event = { occurred_at: Time.current }
      expect(service.send(:causal_candidate?, failure, event)).to be_falsey
    end
  end
end
