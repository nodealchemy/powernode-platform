# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Autonomy::BehavioralFingerprintService do
  let(:account) { create(:account) }
  let(:agent) { create(:ai_agent, account: account) }
  let(:service) { described_class.new(account: account) }

  describe '#record_observation' do
    it 'creates a fingerprint on first observation' do
      result = service.record_observation(agent: agent, metric_name: 'tool_call_rate', value: 5.0)

      expect(result[:anomaly]).to be false
      expect(result[:fingerprint]).to be_persisted
      expect(result[:fingerprint].observation_count).to eq(1)
    end

    it 'detects anomaly when value deviates beyond threshold' do
      fingerprint = Ai::BehavioralFingerprint.create!(
        account: account, agent: agent, metric_name: 'error_rate',
        baseline_mean: 0.1, baseline_stddev: 0.02,
        observation_count: 20, deviation_threshold: 2.0,
        recent_observations: []
      )

      result = service.record_observation(agent: agent, metric_name: 'error_rate', value: 0.5)
      expect(result[:anomaly]).to be true
      expect(result[:z_score]).to be > 2.0
    end

    it 'does not flag anomaly with insufficient data' do
      Ai::BehavioralFingerprint.create!(
        account: account, agent: agent, metric_name: 'cost',
        baseline_mean: 1.0, baseline_stddev: 0.1,
        observation_count: 3, deviation_threshold: 2.0,
        recent_observations: []
      )

      result = service.record_observation(agent: agent, metric_name: 'cost', value: 100.0)
      expect(result[:anomaly]).to be false
    end
  end

  describe '#detect_anomaly' do
    it 'returns insufficient_data for new metrics' do
      result = service.detect_anomaly(agent: agent, metric_name: 'unknown', value: 1.0)
      expect(result[:insufficient_data]).to be true
    end

    it 'detects anomaly without recording' do
      Ai::BehavioralFingerprint.create!(
        account: account, agent: agent, metric_name: 'latency',
        baseline_mean: 100.0, baseline_stddev: 10.0,
        observation_count: 50, deviation_threshold: 2.0,
        recent_observations: []
      )

      result = service.detect_anomaly(agent: agent, metric_name: 'latency', value: 200.0)
      expect(result[:anomaly]).to be true
      expect(result[:insufficient_data]).to be false
    end
  end

  describe '#update_baseline' do
    it 'recalculates mean and stddev from recent observations' do
      observations = (1..20).map do |i|
        { "value" => 10.0 + rand(-1.0..1.0), "timestamp" => (i.hours.ago).iso8601 }
      end

      fingerprint = Ai::BehavioralFingerprint.create!(
        account: account, agent: agent, metric_name: 'rate',
        baseline_mean: 0.0, baseline_stddev: 1.0,
        observation_count: 20, rolling_window_days: 7,
        recent_observations: observations
      )

      service.update_baseline(fingerprint)
      expect(fingerprint.reload.baseline_mean).to be_within(2.0).of(10.0)
    end
  end
end
