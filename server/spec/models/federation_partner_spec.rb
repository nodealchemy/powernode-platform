# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FederationPartner, type: :model do
  describe 'associations' do
    it { should belong_to(:account) }
    it { should belong_to(:created_by).class_name('User').optional }
    it { should belong_to(:approved_by).class_name('User').optional }
    it { should have_many(:a2a_tasks).class_name('Ai::A2aTask') }
  end

  describe 'validations' do
    subject { build(:federation_partner) }

    it { should validate_presence_of(:name) }
    it { should validate_presence_of(:organization_id) }
    it { should validate_presence_of(:endpoint_url) }
    it { should validate_presence_of(:status) }
    it { should validate_uniqueness_of(:organization_id) }
    it { should validate_inclusion_of(:status).in_array(FederationPartner::STATUSES) }
    it { should validate_numericality_of(:trust_level).is_greater_than_or_equal_to(1).is_less_than_or_equal_to(5) }
    it { should validate_numericality_of(:max_requests_per_hour).is_greater_than(0) }

    context 'endpoint_url format' do
      it 'validates URL format' do
        partner = build(:federation_partner, endpoint_url: 'not-a-url')
        expect(partner).not_to be_valid
      end

      it 'accepts valid HTTPS URL' do
        partner = build(:federation_partner, endpoint_url: 'https://partner.example.com/a2a')
        expect(partner).to be_valid
      end
    end
  end

  describe 'scopes' do
    let!(:pending_partner) { create(:federation_partner, :pending) }
    let!(:active_partner) { create(:federation_partner, :active) }
    let!(:suspended_partner) { create(:federation_partner, :suspended) }

    describe '.active' do
      it 'returns only active partners' do
        expect(FederationPartner.active).to include(active_partner)
        expect(FederationPartner.active).not_to include(pending_partner, suspended_partner)
      end
    end

    describe '.pending' do
      it 'returns only pending partners' do
        expect(FederationPartner.pending).to include(pending_partner)
      end
    end
  end

  describe '#approve!' do
    let(:partner) { create(:federation_partner, :pending) }
    let(:user) { create(:user) }

    it 'changes status to active' do
      partner.approve!(user)
      expect(partner.reload.status).to eq('active')
      expect(partner.approved_at).to be_present
      expect(partner.approved_by).to eq(user)
    end
  end

  describe '#suspend!' do
    let(:partner) { create(:federation_partner, :active) }

    it 'changes status to suspended' do
      partner.suspend!(reason: 'Policy violation')
      expect(partner.reload.status).to eq('suspended')
    end
  end

  describe '#reactivate!' do
    let(:partner) { create(:federation_partner, :suspended) }

    it 'changes status to active' do
      partner.reactivate!
      expect(partner.reload.status).to eq('active')
    end
  end

  describe '#revoke!' do
    let(:partner) { create(:federation_partner, :active) }

    it 'changes status to revoked' do
      partner.revoke!
      expect(partner.reload.status).to eq('revoked')
    end
  end

  describe '#valid_token?' do
    let(:partner) { create(:federation_partner) }

    it 'returns false for invalid token' do
      expect(partner.valid_token?('wrong_token')).to be false
    end
  end

  describe '#regenerate_token!' do
    let(:partner) { create(:federation_partner) }

    it 'generates new token' do
      old_hash = partner.federation_token_hash
      new_token = partner.regenerate_token!

      expect(new_token).to be_present
      expect(partner.federation_token_hash).not_to eq(old_hash)
    end
  end

  describe '#increase_trust!' do
    let(:partner) { create(:federation_partner, trust_level: 3) }

    it 'increases trust level' do
      partner.increase_trust!
      expect(partner.reload.trust_level).to eq(4)
    end

    it 'does not exceed max level' do
      partner.update!(trust_level: 5)
      partner.increase_trust!
      expect(partner.reload.trust_level).to eq(5)
    end
  end

  describe '#decrease_trust!' do
    let(:partner) { create(:federation_partner, trust_level: 3) }

    it 'decreases trust level' do
      partner.decrease_trust!
      expect(partner.reload.trust_level).to eq(2)
    end

    it 'does not go below min level' do
      partner.update!(trust_level: 1)
      partner.decrease_trust!
      expect(partner.reload.trust_level).to eq(1)
    end
  end

  describe '#rate_limited?' do
    let(:partner) { create(:federation_partner, max_requests_per_hour: 10) }

    it 'returns false when under limit' do
      expect(partner.rate_limited?).to be false
    end

    it 'returns true when at limit' do
      10.times { partner.increment_request_count! }
      expect(partner.rate_limited?).to be true
    end
  end
end
