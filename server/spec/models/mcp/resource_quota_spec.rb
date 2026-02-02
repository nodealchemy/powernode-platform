# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mcp::ResourceQuota, type: :model do
  describe 'associations' do
    it { should belong_to(:account) }
  end

  describe 'validations' do
    subject { build(:mcp_resource_quota) }

    it { should validate_numericality_of(:max_concurrent_containers).is_greater_than(0) }
    it { should validate_numericality_of(:max_containers_per_hour).is_greater_than(0) }
    it { should validate_numericality_of(:max_containers_per_day).is_greater_than(0) }
    it { should validate_numericality_of(:max_memory_mb).is_greater_than(0) }
    it { should validate_numericality_of(:max_cpu_millicores).is_greater_than(0) }
  end

  describe '#can_execute?' do
    let(:quota) { create(:mcp_resource_quota, :default) }

    it 'returns true when under all limits' do
      expect(quota.can_execute?).to be true
    end

    context 'when at concurrent limit' do
      let(:quota) { create(:mcp_resource_quota, :at_limit) }

      it 'returns false' do
        expect(quota.can_execute?).to be false
      end
    end

    context 'when at hourly limit' do
      let(:quota) { create(:mcp_resource_quota, max_containers_per_hour: 10, containers_used_this_hour: 10) }

      it 'returns false' do
        expect(quota.can_execute?).to be false
      end
    end
  end

  describe '#increment_usage!' do
    let(:quota) { create(:mcp_resource_quota) }

    it 'increments concurrent count' do
      expect { quota.increment_usage! }.to change { quota.current_running_containers }.by(1)
    end

    it 'increments hourly count' do
      expect { quota.increment_usage! }.to change { quota.containers_used_this_hour }.by(1)
    end

    it 'increments daily count' do
      expect { quota.increment_usage! }.to change { quota.containers_used_today }.by(1)
    end
  end

  describe '#decrement_running!' do
    let(:quota) { create(:mcp_resource_quota, current_running_containers: 3) }

    it 'decrements concurrent count' do
      expect { quota.decrement_running! }.to change { quota.current_running_containers }.by(-1)
    end

    it 'does not go below zero' do
      quota.update!(current_running_containers: 0)
      quota.decrement_running!
      expect(quota.current_running_containers).to eq(0)
    end
  end

  describe '#quota_status' do
    let(:quota) { create(:mcp_resource_quota, :near_limit) }

    it 'returns status hash with usage information' do
      status = quota.quota_status

      expect(status).to include(:concurrent, :hourly, :daily)
      expect(status[:concurrent][:used]).to eq(quota.current_running_containers)
      expect(status[:concurrent][:limit]).to eq(quota.max_concurrent_containers)
    end
  end

  describe '#domain_allowed?' do
    context 'when network access is disabled' do
      let(:quota) { create(:mcp_resource_quota, allow_network_access: false) }

      it 'returns true (method checks allowed domains, not network access)' do
        # domain_allowed? returns true when network is disabled (no domain check needed)
        expect(quota.domain_allowed?('api.openai.com')).to be true
      end
    end

    context 'when network access is enabled with whitelist' do
      let(:quota) { create(:mcp_resource_quota, :with_domain_whitelist) }

      it 'returns true for whitelisted domains' do
        expect(quota.domain_allowed?('api.openai.com')).to be true
      end

      it 'returns false for non-whitelisted domains' do
        expect(quota.domain_allowed?('evil.com')).to be false
      end
    end

    context 'when network access is enabled without whitelist' do
      let(:quota) { create(:mcp_resource_quota, allow_network_access: true, allowed_egress_domains: []) }

      it 'returns true for any domain' do
        expect(quota.domain_allowed?('any-domain.com')).to be true
      end
    end
  end

  describe '#calculate_overage_cost' do
    let(:quota) { create(:mcp_resource_quota, :with_overage, max_containers_per_day: 100) }

    it 'calculates overage cost' do
      expect(quota.calculate_overage_cost(150)).to be > 0
    end

    it 'returns 0 when under limit' do
      expect(quota.calculate_overage_cost(50)).to eq(0)
    end
  end
end
