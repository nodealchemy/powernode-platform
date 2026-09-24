# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Monitoring::UnifiedService, 'alert identity and lifecycle' do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:service) { described_class.new(account: account) }
  let(:redis) { Powernode::Redis.client }

  before { allow(AiOrchestrationChannel).to receive(:broadcast_alert) }
  after { redis.del("alerts:#{account.id}") }

  it 'gives every triggered alert a UUIDv7 id and open lifecycle flags' do
    alert = service.trigger_alert('high_latency', {})

    expect(alert[:id]).to match(/\A\h{8}-\h{4}-7\h{3}-\h{4}-\h{12}\z/)
    expect(alert).to include(acknowledged: false, resolved: false)
    expect(service.get_active_alerts.map { |a| a[:id] }).to eq([ alert[:id] ])
  end

  it 'acknowledges and then resolves the stored alert in place' do
    id = service.trigger_alert('high_latency', {})[:id]

    acknowledged = service.acknowledge_alert(id, user: user, note: 'on it')
    resolved = service.resolve_alert(id, user: user, note: 'done')

    expect(acknowledged).to include(acknowledged: true, acknowledged_by: user.id, acknowledgement_note: 'on it')
    expect(resolved).to include(acknowledged: true, resolved: true, resolved_by: user.id, resolution_note: 'done')
    expect(service.get_active_alerts).to contain_exactly(include(id: id, resolved: true))
  end

  it 'returns nil for an id the account does not own' do
    other = described_class.new(account: create(:account))
    id = other.trigger_alert('high_latency', {})[:id]

    expect(service.acknowledge_alert(id, user: user)).to be_nil
    expect(service.resolve_alert(id, user: user)).to be_nil
  ensure
    redis.del("alerts:#{other.instance_variable_get(:@account).id}") if other
  end
end
