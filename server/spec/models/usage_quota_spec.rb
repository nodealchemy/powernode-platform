# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UsageQuota, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:usage_meter) }
    it { is_expected.to belong_to(:plan).optional }
  end

  describe 'validations' do
    subject { build(:usage_quota) }

    # NOTE: shoulda-matchers validate_uniqueness_of doesn't work with UUID primary keys
    # because PostgreSQL normalizes UUID case, confusing the case-sensitivity check.
    it 'validates uniqueness of account_id scoped to usage_meter_id' do
      existing = create(:usage_quota)
      duplicate = build(:usage_quota,
        account: existing.account,
        usage_meter: existing.usage_meter)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:account_id]).to be_present
    end

    it 'allows same account with different usage_meter' do
      existing = create(:usage_quota)
      other = build(:usage_quota,
        account: existing.account,
        usage_meter: create(:usage_meter))
      expect(other).to be_valid
    end
    it { is_expected.to validate_numericality_of(:soft_limit).is_greater_than(0).allow_nil }
    it { is_expected.to validate_numericality_of(:hard_limit).is_greater_than(0).allow_nil }
    it { is_expected.to validate_numericality_of(:overage_rate).is_greater_than_or_equal_to(0).allow_nil }

    describe 'custom validations' do
      it 'validates hard_limit is greater than or equal to soft_limit' do
        quota = build(:usage_quota, soft_limit: 1000, hard_limit: 500)
        expect(quota).not_to be_valid
        expect(quota.errors[:hard_limit]).to include('must be greater than or equal to soft limit')
      end

      it 'allows hard_limit equal to soft_limit' do
        quota = build(:usage_quota, soft_limit: 1000, hard_limit: 1000)
        expect(quota).to be_valid
      end

      it 'validates critical_threshold_percent is greater than warning_threshold_percent' do
        quota = build(:usage_quota, warning_threshold_percent: 90, critical_threshold_percent: 80)
        expect(quota).not_to be_valid
        expect(quota.errors[:critical_threshold_percent]).to include('must be greater than warning threshold')
      end

      it 'allows critical_threshold_percent equal to warning when only one is set' do
        quota = build(:usage_quota, warning_threshold_percent: nil, critical_threshold_percent: 80)
        expect(quota).to be_valid
      end
    end
  end

  describe 'scopes' do
    describe '.exceeded' do
      it 'returns quotas where current usage exceeds the effective limit' do
        exceeded = create(:usage_quota, soft_limit: 100, hard_limit: 200, current_usage: 150)
        not_exceeded = create(:usage_quota, soft_limit: 100, hard_limit: 200, current_usage: 50)

        expect(UsageQuota.exceeded).to include(exceeded)
        expect(UsageQuota.exceeded).not_to include(not_exceeded)
      end
    end

    describe '.near_limit' do
      it 'returns quotas approaching their limits (>= 80%)' do
        near_limit = create(:usage_quota, soft_limit: 100, hard_limit: 200, current_usage: 85)
        not_near = create(:usage_quota, soft_limit: 100, hard_limit: 200, current_usage: 50)

        expect(UsageQuota.near_limit).to include(near_limit)
        expect(UsageQuota.near_limit).not_to include(not_near)
      end
    end
  end

  describe 'instance methods' do
    describe '#effective_limit' do
      it 'returns soft_limit when both limits are set' do
        quota = create(:usage_quota, soft_limit: 1000, hard_limit: 1500)
        expect(quota.effective_limit).to eq(1000)
      end

      it 'returns soft_limit when only soft_limit is set' do
        quota = create(:usage_quota, soft_limit: 1000, hard_limit: nil)
        expect(quota.effective_limit).to eq(1000)
      end

      it 'returns hard_limit when soft_limit is not set' do
        quota = create(:usage_quota, soft_limit: nil, hard_limit: 1500)
        expect(quota.effective_limit).to eq(1500)
      end

      it 'returns nil when no limits are set' do
        quota = create(:usage_quota, soft_limit: nil, hard_limit: nil)
        expect(quota.effective_limit).to be_nil
      end
    end

    describe '#usage_percent' do
      it 'calculates the percentage of effective limit used' do
        quota = create(:usage_quota, soft_limit: 1000, hard_limit: 1500, current_usage: 250)
        expect(quota.usage_percent).to eq(25.0)
      end

      it 'caps at 100%' do
        quota = create(:usage_quota, soft_limit: 1000, hard_limit: 1500, current_usage: 1100)
        expect(quota.usage_percent).to eq(100)
      end

      it 'returns 0 when no effective limit is set' do
        quota = create(:usage_quota, soft_limit: nil, hard_limit: nil, current_usage: 100)
        expect(quota.usage_percent).to eq(0)
      end
    end

    describe '#remaining' do
      it 'calculates remaining quota based on effective limit' do
        quota = create(:usage_quota, soft_limit: 1000, hard_limit: 1500, current_usage: 400)
        expect(quota.remaining).to eq(600)
      end

      it 'returns nil when no limits are set' do
        quota = create(:usage_quota, soft_limit: nil, hard_limit: nil, current_usage: 100)
        expect(quota.remaining).to be_nil
      end

      it 'returns 0 when usage exceeds limit (never negative)' do
        quota = create(:usage_quota, soft_limit: 1000, hard_limit: 1000, current_usage: 1200)
        expect(quota.remaining).to eq(0)
      end
    end

    describe '#exceeded?' do
      it 'returns true when current usage exceeds effective limit' do
        quota = create(:usage_quota, soft_limit: 1000, hard_limit: 1500, current_usage: 1100)
        expect(quota.exceeded?).to be true
      end

      it 'returns false when current usage is below effective limit' do
        quota = create(:usage_quota, soft_limit: 1000, hard_limit: 1500, current_usage: 900)
        expect(quota.exceeded?).to be false
      end

      it 'returns false when no effective limit is set' do
        quota = create(:usage_quota, soft_limit: nil, hard_limit: nil, current_usage: 1000)
        expect(quota.exceeded?).to be false
      end
    end

    describe '#hard_exceeded?' do
      it 'returns true when current usage exceeds hard limit' do
        quota = create(:usage_quota, hard_limit: 1500, current_usage: 1600)
        expect(quota.hard_exceeded?).to be true
      end

      it 'returns false when current usage is below hard limit' do
        quota = create(:usage_quota, hard_limit: 1500, current_usage: 1400)
        expect(quota.hard_exceeded?).to be false
      end

      it 'returns false when hard limit is not set' do
        quota = create(:usage_quota, hard_limit: nil, current_usage: 1000)
        expect(quota.hard_exceeded?).to be false
      end
    end

    describe '#at_warning_threshold?' do
      it 'returns true when usage percent is at or above warning threshold' do
        quota = create(:usage_quota,
          soft_limit: 1000,
          hard_limit: 1500,
          current_usage: 850,
          warning_threshold_percent: 80
        )
        expect(quota.at_warning_threshold?).to be true
      end

      it 'returns false when usage percent is below warning threshold' do
        quota = create(:usage_quota,
          soft_limit: 1000,
          hard_limit: 1500,
          current_usage: 750,
          warning_threshold_percent: 80
        )
        expect(quota.at_warning_threshold?).to be false
      end

      it 'returns false when warning_threshold_percent is nil' do
        quota = create(:usage_quota,
          soft_limit: 1000,
          hard_limit: 1500,
          current_usage: 900,
          warning_threshold_percent: nil
        )
        expect(quota.at_warning_threshold?).to be false
      end
    end

    describe '#at_critical_threshold?' do
      it 'returns true when usage percent is at or above critical threshold' do
        quota = create(:usage_quota,
          soft_limit: 1000,
          hard_limit: 1500,
          current_usage: 960,
          critical_threshold_percent: 95
        )
        expect(quota.at_critical_threshold?).to be true
      end

      it 'returns false when usage percent is below critical threshold' do
        quota = create(:usage_quota,
          soft_limit: 1000,
          hard_limit: 1500,
          current_usage: 900,
          critical_threshold_percent: 95
        )
        expect(quota.at_critical_threshold?).to be false
      end

      it 'returns false when critical_threshold_percent is nil' do
        quota = create(:usage_quota,
          soft_limit: 1000,
          hard_limit: 1500,
          current_usage: 999,
          critical_threshold_percent: nil
        )
        expect(quota.at_critical_threshold?).to be false
      end
    end

    describe '#overage_amount' do
      it 'calculates overage cost when exceeded, overage allowed, and rate set' do
        quota = create(:usage_quota,
          soft_limit: 1000,
          hard_limit: 1500,
          current_usage: 1200,
          allow_overage: true,
          overage_rate: 0.05
        )
        # exceeded? is true (1200 >= 1000 effective_limit)
        # overage_units = 1200 - 1000 = 200
        # overage_amount = 200 * 0.05 = 10.0
        expect(quota.overage_amount).to eq(10.0)
      end

      it 'returns 0 when usage is below effective limit' do
        quota = create(:usage_quota,
          soft_limit: 1000,
          hard_limit: 1500,
          current_usage: 800,
          allow_overage: true,
          overage_rate: 0.05
        )
        expect(quota.overage_amount).to eq(0)
      end

      it 'returns 0 when allow_overage is false' do
        quota = create(:usage_quota,
          soft_limit: 1000,
          hard_limit: 1500,
          current_usage: 1200,
          allow_overage: false,
          overage_rate: 0.05
        )
        expect(quota.overage_amount).to eq(0)
      end

      it 'returns 0 when overage_rate is nil' do
        quota = create(:usage_quota,
          soft_limit: 1000,
          hard_limit: 1500,
          current_usage: 1200,
          allow_overage: true,
          overage_rate: nil
        )
        expect(quota.overage_amount).to eq(0)
      end
    end

    describe '#can_use?' do
      it 'returns true when usage plus amount is within hard limit and overage not allowed' do
        quota = create(:usage_quota, hard_limit: 1500, current_usage: 1000, allow_overage: false)
        expect(quota.can_use?(400)).to be true
      end

      it 'returns false when usage plus amount exceeds hard limit and overage not allowed' do
        quota = create(:usage_quota, hard_limit: 1500, current_usage: 1000, allow_overage: false)
        expect(quota.can_use?(600)).to be false
      end

      it 'returns true when overage is allowed even if hard limit would be exceeded' do
        quota = create(:usage_quota,
          soft_limit: 1000,
          hard_limit: 1500,
          current_usage: 1400,
          allow_overage: true
        )
        expect(quota.can_use?(200)).to be true
      end

      it 'returns true when hard limit is nil' do
        quota = create(:usage_quota, soft_limit: 1000, hard_limit: nil, current_usage: 1000)
        expect(quota.can_use?(500)).to be true
      end
    end

    describe '#reset_usage!' do
      it 'resets current usage to 0 and updates period timestamps' do
        quota = create(:usage_quota, current_usage: 500)
        quota.reset_usage!
        quota.reload

        expect(quota.current_usage).to eq(0)
        expect(quota.current_period_start).to be_present
      end
    end

    describe '#summary' do
      it 'returns a hash with quota summary information' do
        quota = create(:usage_quota)
        result = quota.summary

        expect(result).to be_a(Hash)
        expect(result[:id]).to eq(quota.id)
        expect(result[:soft_limit]).to eq(quota.soft_limit)
        expect(result[:hard_limit]).to eq(quota.hard_limit)
        expect(result[:current_usage]).to eq(quota.current_usage)
        expect(result[:remaining]).to eq(quota.remaining)
        expect(result[:usage_percent]).to eq(quota.usage_percent)
        expect(result[:exceeded]).to eq(quota.exceeded?)
        expect(result[:allow_overage]).to eq(quota.allow_overage)
        expect(result[:overage_rate]).to eq(quota.overage_rate)
        expect(result[:overage_amount]).to eq(quota.overage_amount)
        expect(result[:at_warning]).to eq(quota.at_warning_threshold?)
        expect(result[:at_critical]).to eq(quota.at_critical_threshold?)
      end
    end
  end
end
