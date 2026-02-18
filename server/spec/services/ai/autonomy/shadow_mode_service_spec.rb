# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Autonomy::ShadowModeService do
  let(:account) { create(:account) }
  let(:agent) { create(:ai_agent, account: account) }
  let(:service) { described_class.new(account: account) }

  describe '#execute_shadow' do
    it 'creates a shadow execution record' do
      exec = service.execute_shadow(
        agent: agent,
        action_type: 'execute_tool',
        input: { prompt: 'test' },
        shadow_output: { result: 'shadow_answer' },
        reference_output: { result: 'shadow_answer' }
      )

      expect(exec).to be_persisted
      expect(exec.agreed).to be true
      expect(exec.agreement_score).to eq(1.0)
    end

    it 'records disagreement when outputs differ' do
      exec = service.execute_shadow(
        agent: agent,
        action_type: 'execute_tool',
        input: { prompt: 'test' },
        shadow_output: { result: 'a', extra: 'b' },
        reference_output: { result: 'c', extra: 'd' }
      )

      expect(exec.agreed).to be false
      expect(exec.agreement_score).to be < 0.8
    end
  end

  describe '#compare_outputs' do
    it 'returns exact match for identical outputs' do
      result = service.compare_outputs({ a: 1 }, { a: 1 })
      expect(result[:agreed]).to be true
      expect(result[:score]).to eq(1.0)
    end

    it 'calculates partial agreement' do
      result = service.compare_outputs({ a: 1, b: 2 }, { a: 1, b: 3 })
      expect(result[:score]).to eq(0.5)
    end

    it 'handles empty reference' do
      result = service.compare_outputs({ a: 1 }, {})
      expect(result[:agreed]).to be false
    end
  end

  describe '#agreement_rate' do
    before do
      3.times { service.execute_shadow(agent: agent, action_type: 'test', input: {}, shadow_output: { r: 1 }, reference_output: { r: 1 }) }
      2.times { service.execute_shadow(agent: agent, action_type: 'test', input: {}, shadow_output: { r: 1 }, reference_output: { r: 2 }) }
    end

    it 'calculates correct agreement rate' do
      result = service.agreement_rate(agent: agent)
      expect(result[:total]).to eq(5)
      expect(result[:agreed]).to eq(3)
      expect(result[:rate]).to eq(0.6)
    end
  end
end
