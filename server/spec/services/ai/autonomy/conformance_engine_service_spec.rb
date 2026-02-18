# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Autonomy::ConformanceEngineService do
  let(:account) { create(:account) }
  let(:agent) { create(:ai_agent, account: account) }
  let(:service) { described_class.new(account: account) }
  let(:telemetry) { Ai::Autonomy::TelemetryService.new(account: account) }

  describe '#check_event' do
    context 'when all required prior events exist' do
      it 'reports conformant' do
        telemetry.record_event(agent: agent, category: 'action', event_type: 'action_approved')
        telemetry.record_event(agent: agent, category: 'security', event_type: 'anomaly_scanned')

        result = service.check_event(agent: agent, event_type: 'action_executed')
        expect(result[:conformant]).to be true
        expect(result[:violations]).to be_empty
      end
    end

    context 'when required prior event is missing' do
      it 'reports violation' do
        result = service.check_event(agent: agent, event_type: 'action_executed')
        expect(result[:conformant]).to be false
        expect(result[:violations].size).to be >= 1

        violation = result[:violations].first
        expect(violation[:rule]).to be_present
        expect(violation[:severity]).to be_present
      end
    end

    context 'when event has no applicable rules' do
      it 'reports conformant' do
        result = service.check_event(agent: agent, event_type: 'unknown_event')
        expect(result[:conformant]).to be true
      end
    end
  end

  describe '#effective_rules' do
    it 'returns default rules when no custom config exists' do
      rules = service.effective_rules
      expect(rules).to eq(described_class::DEFAULT_RULES)
    end
  end
end
