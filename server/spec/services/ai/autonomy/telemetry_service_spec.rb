# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Autonomy::TelemetryService do
  let(:account) { create(:account) }
  let(:agent) { create(:ai_agent, account: account) }
  let(:service) { described_class.new(account: account) }

  describe '#record_event' do
    it 'creates a telemetry event with auto-sequence' do
      event = service.record_event(
        agent: agent,
        category: 'action',
        event_type: 'tool_executed',
        data: { tool: 'search', duration_ms: 150 },
        outcome: 'success'
      )

      expect(event).to be_persisted
      expect(event.sequence_number).to eq(0)
      expect(event.event_category).to eq('action')
      expect(event.correlation_id).to be_present
    end

    it 'auto-increments sequence within correlation' do
      correlation = SecureRandom.uuid
      e1 = service.record_event(agent: agent, category: 'action', event_type: 'start', correlation_id: correlation)
      e2 = service.record_event(agent: agent, category: 'action', event_type: 'end', correlation_id: correlation)

      expect(e1.sequence_number).to eq(0)
      expect(e2.sequence_number).to eq(1)
    end
  end

  describe '#query_events' do
    before do
      service.record_event(agent: agent, category: 'action', event_type: 'test1')
      service.record_event(agent: agent, category: 'trust', event_type: 'test2')
      service.record_event(agent: agent, category: 'action', event_type: 'test3')
    end

    it 'returns all events for account' do
      events = service.query_events
      expect(events.count).to eq(3)
    end

    it 'filters by category' do
      events = service.query_events(category: 'action')
      expect(events.count).to eq(2)
    end

    it 'filters by agent' do
      other = create(:ai_agent, account: account)
      service.record_event(agent: other, category: 'action', event_type: 'other')

      events = service.query_events(agent_id: agent.id)
      expect(events.count).to eq(3)
    end
  end

  describe '#build_causal_chain' do
    it 'builds ordered chain from parent-child events' do
      correlation = SecureRandom.uuid
      root = service.record_event(agent: agent, category: 'action', event_type: 'start', correlation_id: correlation)
      child1 = service.record_event(agent: agent, category: 'action', event_type: 'step1', correlation_id: correlation, parent_event_id: root.id)
      child2 = service.record_event(agent: agent, category: 'action', event_type: 'step2', correlation_id: correlation, parent_event_id: root.id)

      chain = service.build_causal_chain(child1)
      expect(chain.size).to eq(3)
      expect(chain.first.id).to eq(root.id)
    end
  end
end
