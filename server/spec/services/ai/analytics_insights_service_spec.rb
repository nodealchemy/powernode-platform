# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::AnalyticsInsightsService, type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:provider) { create(:ai_provider, account: account, slug: 'openai-analytics') }
  let(:agent) { create(:ai_agent, account: account, provider: provider, agent_type: 'assistant') }

  describe '#initialize' do
    it 'initializes with account keyword argument' do
      service = described_class.new(account: account)
      expect(service.account).to eq(account)
    end

    it 'sets default time_range to 30 days' do
      service = described_class.new(account: account)
      expect(service.time_range).to eq(30.days)
    end

    it 'accepts custom time_range' do
      service = described_class.new(account: account, time_range: 7.days)
      expect(service.time_range).to eq(7.days)
    end

    it 'can be initialized with various time ranges' do
      expect { described_class.new(account: account, time_range: 1.day) }.not_to raise_error
      expect { described_class.new(account: account, time_range: 90.days) }.not_to raise_error
    end
  end

  describe '#base_executions_query' do
    let(:service) { described_class.new(account: account) }

    before do
      create_list(:ai_agent_execution, 3, :completed, account: account, agent: agent)
    end

    it 'returns an ActiveRecord relation' do
      result = service.send(:base_executions_query)
      expect(result).to be_a(ActiveRecord::Relation)
    end

    it 'scopes to account' do
      other_account = create(:account)
      other_agent = create(:ai_agent, account: other_account, provider: provider, agent_type: 'assistant')
      create(:ai_agent_execution, :completed, account: other_account, agent: other_agent)

      result = service.send(:base_executions_query)
      expect(result.pluck(:account_id).uniq).to eq([ account.id ])
    end
  end

  describe 'cache_key' do
    let(:service) { described_class.new(account: account) }

    it 'generates a cache key' do
      key = service.send(:cache_key)
      expect(key).to be_a(String)
    end
  end

  describe 'service instantiation with different accounts' do
    it 'creates separate instances for different accounts' do
      account1 = create(:account)
      account2 = create(:account)

      service1 = described_class.new(account: account1)
      service2 = described_class.new(account: account2)

      expect(service1.account).not_to eq(service2.account)
    end
  end

  describe 'time_range behavior' do
    it 'calculates start_date based on time_range' do
      service = described_class.new(account: account, time_range: 7.days)
      start_date = service.instance_variable_get(:@start_date)
      expect(start_date).to be_within(1.minute).of(7.days.ago)
    end

    it 'sets end_date to current time' do
      service = described_class.new(account: account)
      end_date = service.instance_variable_get(:@end_date)
      expect(end_date).to be_within(1.minute).of(Time.current)
    end
  end
end
