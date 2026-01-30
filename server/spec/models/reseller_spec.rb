# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Reseller, type: :model do
  describe 'associations' do
    it { should belong_to(:account) }
    it { should belong_to(:primary_user).class_name('User') }
    it { should belong_to(:approved_by).class_name('User').optional }
    it { should have_many(:commissions).class_name('ResellerCommission').dependent(:destroy) }
    it { should have_many(:payouts).class_name('ResellerPayout').dependent(:destroy) }
    it { should have_many(:referrals).class_name('ResellerReferral').dependent(:destroy) }
  end

  describe 'validations' do
    subject { build(:reseller) }

    it { should validate_presence_of(:company_name) }
    it { should validate_length_of(:company_name).is_at_least(2).is_at_most(200) }
    it { should validate_presence_of(:contact_email) }
    it { should validate_presence_of(:tier) }
    it { should validate_inclusion_of(:tier).in_array(%w[bronze silver gold platinum]) }
    it { should validate_presence_of(:status) }
    it { should validate_inclusion_of(:status).in_array(%w[pending approved active suspended terminated]) }
    it { should validate_numericality_of(:commission_percentage).is_greater_than_or_equal_to(0).is_less_than_or_equal_to(50) }

    it 'validates email format' do
      reseller = build(:reseller, contact_email: 'invalid')
      expect(reseller).not_to be_valid
      expect(reseller.errors[:contact_email]).to be_present
    end

    it 'validates referral_code uniqueness' do
      existing = create(:reseller)
      new_reseller = build(:reseller, referral_code: existing.referral_code)
      expect(new_reseller).not_to be_valid
    end

    it 'auto-generates referral_code on create' do
      reseller = create(:reseller)
      expect(reseller.referral_code).to be_present
      expect(reseller.referral_code.length).to be >= 4
    end

    it 'auto-sets commission by tier on create' do
      reseller = create(:reseller, tier: 'silver')
      expect(reseller.commission_percentage).to eq(15.0)
    end
  end

  describe 'scopes' do
    let!(:active_reseller) { create(:reseller, status: 'active') }
    let!(:pending_reseller) { create(:reseller, :pending) }
    let!(:gold_reseller) { create(:reseller, :gold, status: 'active') }

    describe '.active' do
      it 'returns only active resellers' do
        expect(Reseller.active).to include(active_reseller, gold_reseller)
        expect(Reseller.active).not_to include(pending_reseller)
      end
    end

    describe '.pending' do
      it 'returns only pending resellers' do
        expect(Reseller.pending).to include(pending_reseller)
        expect(Reseller.pending).not_to include(active_reseller)
      end
    end

    describe '.by_tier' do
      it 'returns resellers of specified tier' do
        expect(Reseller.by_tier('gold')).to include(gold_reseller)
        expect(Reseller.by_tier('gold')).not_to include(active_reseller)
      end
    end

    describe '.with_pending_payout' do
      it 'returns resellers with pending payouts' do
        active_reseller.update!(pending_payout: 100)
        expect(Reseller.with_pending_payout).to include(active_reseller)
        expect(Reseller.with_pending_payout).not_to include(pending_reseller)
      end
    end
  end

  describe 'instance methods' do
    let(:reseller) { create(:reseller, status: 'active') }

    describe '#active?' do
      it 'returns true when status is active' do
        expect(reseller.active?).to be true
      end

      it 'returns false otherwise' do
        reseller.status = 'pending'
        expect(reseller.active?).to be false
      end
    end

    describe '#pending?' do
      it 'returns true when status is pending' do
        reseller.status = 'pending'
        expect(reseller.pending?).to be true
      end
    end

    describe '#suspended?' do
      it 'returns true when status is suspended' do
        reseller.status = 'suspended'
        expect(reseller.suspended?).to be true
      end
    end

    describe '#terminated?' do
      it 'returns true when status is terminated' do
        reseller.status = 'terminated'
        expect(reseller.terminated?).to be true
      end
    end

    describe '#minimum_payout_amount' do
      it 'returns 50' do
        expect(reseller.minimum_payout_amount).to eq(50.0)
      end
    end

    describe '#can_receive_payouts?' do
      it 'returns true when active and has sufficient pending payout' do
        reseller.pending_payout = 100
        expect(reseller.can_receive_payouts?).to be true
      end

      it 'returns false when not active' do
        reseller.status = 'pending'
        reseller.pending_payout = 100
        expect(reseller.can_receive_payouts?).to be false
      end

      it 'returns false when pending payout is below minimum' do
        reseller.pending_payout = 25
        expect(reseller.can_receive_payouts?).to be false
      end
    end

    describe '#approve!' do
      let(:approver) { create(:user) }
      let(:pending) { create(:reseller, :pending) }

      it 'updates status to approved' do
        pending.approve!(approver)
        expect(pending.status).to eq('approved')
        expect(pending.approved_by).to eq(approver)
        expect(pending.approved_at).to be_present
      end

      it 'returns false if not pending' do
        reseller.status = 'active'
        expect(reseller.approve!(approver)).to be false
      end
    end

    describe '#activate!' do
      let(:approved) { create(:reseller, :approved) }

      it 'updates status to active' do
        approved.activate!
        expect(approved.status).to eq('active')
        expect(approved.activated_at).to be_present
      end

      it 'returns false if not approved' do
        reseller.status = 'pending'
        expect(reseller.activate!).to be false
      end
    end

    describe '#suspend!' do
      it 'updates status to suspended' do
        reseller.suspend!
        expect(reseller.status).to eq('suspended')
      end

      it 'returns false if terminated' do
        reseller.status = 'terminated'
        expect(reseller.suspend!).to be false
      end
    end

    describe '#terminate!' do
      it 'updates status to terminated' do
        reseller.terminate!
        expect(reseller.status).to eq('terminated')
      end
    end

    describe '#next_tier_name' do
      it 'returns silver for bronze' do
        reseller.tier = 'bronze'
        expect(reseller.next_tier_name).to eq('silver')
      end

      it 'returns gold for silver' do
        reseller.tier = 'silver'
        expect(reseller.next_tier_name).to eq('gold')
      end

      it 'returns platinum for gold' do
        reseller.tier = 'gold'
        expect(reseller.next_tier_name).to eq('platinum')
      end

      it 'returns nil for platinum' do
        reseller.tier = 'platinum'
        expect(reseller.next_tier_name).to be_nil
      end
    end

    describe '#tier_benefits' do
      it 'returns benefits for current tier' do
        reseller.tier = 'bronze'
        benefits = reseller.tier_benefits
        expect(benefits[:commission]).to eq(10.0)
        expect(benefits[:min_referrals]).to eq(0)
      end
    end

    describe '#dashboard_stats' do
      it 'returns hash with expected keys' do
        stats = reseller.dashboard_stats
        expect(stats).to have_key(:tier)
        expect(stats).to have_key(:commission_percentage)
        expect(stats).to have_key(:lifetime_earnings)
        expect(stats).to have_key(:pending_payout)
        expect(stats).to have_key(:can_request_payout)
      end
    end
  end

  describe 'TIER_BENEFITS constant' do
    it 'defines benefits for all tiers' do
      expect(Reseller::TIER_BENEFITS.keys).to contain_exactly('bronze', 'silver', 'gold', 'platinum')
    end

    it 'includes required keys for each tier' do
      Reseller::TIER_BENEFITS.each do |_tier, benefits|
        expect(benefits).to have_key(:commission)
        expect(benefits).to have_key(:min_referrals)
        expect(benefits).to have_key(:revenue_threshold)
      end
    end
  end
end
