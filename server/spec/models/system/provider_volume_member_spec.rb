# frozen_string_literal: true

require 'rails_helper'

RSpec.describe System::ProviderVolumeMember, type: :model do
  let(:account) { create(:account) }
  let(:volume) { create(:system_provider_volume, account: account, raid_level: 0) }

  describe 'associations' do
    it 'belongs to provider_volume' do
      member = create(:system_provider_volume_member, provider_volume: volume, member_index: 0)
      expect(member.provider_volume).to eq(volume)
    end
  end

  describe 'delegations' do
    let(:member) { create(:system_provider_volume_member, provider_volume: volume) }

    it 'delegates account to provider_volume' do
      expect(member.account).to eq(volume.account)
    end

    it 'delegates account_id to provider_volume' do
      expect(member.account_id).to eq(volume.account_id)
    end
  end

  describe 'validations' do
    subject { build(:system_provider_volume_member, provider_volume: volume) }

    it { should validate_presence_of(:size_gb) }
    it { should validate_presence_of(:status) }
    it { should validate_presence_of(:member_index) }
    it { should validate_numericality_of(:size_gb).only_integer.is_greater_than(0) }
    it { should validate_inclusion_of(:status).in_array(System::ProviderVolumeMember::STATUSES) }

    it 'validates uniqueness of member_index scoped to provider_volume' do
      create(:system_provider_volume_member, provider_volume: volume, member_index: 0)
      duplicate = build(:system_provider_volume_member, provider_volume: volume, member_index: 0)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:member_index]).to include('has already been taken')
    end
  end

  describe 'scopes' do
    let!(:pending_member) { create(:system_provider_volume_member, provider_volume: volume, status: 'pending', member_index: 0) }
    let!(:available_member) { create(:system_provider_volume_member, provider_volume: volume, status: 'available', member_index: 1) }
    let!(:attached_member) { create(:system_provider_volume_member, provider_volume: volume, status: 'attached', member_index: 2) }
    let!(:error_member) { create(:system_provider_volume_member, provider_volume: volume, status: 'error', member_index: 3) }
    let!(:deleted_member) { create(:system_provider_volume_member, provider_volume: volume, status: 'deleted', member_index: 4) }

    describe '.pending' do
      it 'returns only pending members' do
        expect(described_class.pending).to contain_exactly(pending_member)
      end
    end

    describe '.available' do
      it 'returns only available members' do
        expect(described_class.available).to contain_exactly(available_member)
      end
    end

    describe '.attached' do
      it 'returns only attached members' do
        expect(described_class.attached).to contain_exactly(attached_member)
      end
    end

    describe '.errored' do
      it 'returns only error members' do
        expect(described_class.errored).to contain_exactly(error_member)
      end
    end

    describe '.deleted' do
      it 'returns only deleted members' do
        expect(described_class.deleted).to contain_exactly(deleted_member)
      end
    end

    describe '.ordered' do
      it 'orders by member_index ascending' do
        expect(described_class.ordered.pluck(:member_index)).to eq([0, 1, 2, 3, 4])
      end
    end

    describe '.active' do
      it 'excludes deleted and error members' do
        expect(described_class.active).to contain_exactly(pending_member, available_member, attached_member)
      end
    end
  end

  describe 'status predicates' do
    let(:member) { create(:system_provider_volume_member, provider_volume: volume, status: 'available', member_index: 0) }

    it 'responds to status predicates' do
      expect(member.available?).to be true
      expect(member.pending?).to be false
      expect(member.attached?).to be false
    end
  end

  describe '#ready?' do
    let(:member) { build(:system_provider_volume_member, provider_volume: volume) }

    it 'returns true when available' do
      member.status = 'available'
      expect(member.ready?).to be true
    end

    it 'returns true when attached' do
      member.status = 'attached'
      expect(member.ready?).to be true
    end

    it 'returns false when pending' do
      member.status = 'pending'
      expect(member.ready?).to be false
    end

    it 'returns false when error' do
      member.status = 'error'
      expect(member.ready?).to be false
    end
  end

  describe '#can_delete?' do
    let(:member) { build(:system_provider_volume_member, provider_volume: volume) }

    it 'returns true when not attached' do
      member.status = 'available'
      expect(member.can_delete?).to be true
    end

    it 'returns false when attached' do
      member.status = 'attached'
      expect(member.can_delete?).to be false
    end
  end

  describe '#provider' do
    let(:member) { create(:system_provider_volume_member, provider_volume: volume, member_index: 0) }

    it 'returns the provider from the parent volume' do
      expect(member.provider).to eq(volume.provider)
    end
  end

  describe '#provider_region' do
    let(:member) { create(:system_provider_volume_member, provider_volume: volume, member_index: 0) }

    it 'returns the provider_region from the parent volume' do
      expect(member.provider_region).to eq(volume.provider_region)
    end
  end

  describe '#display_name' do
    let(:member) { create(:system_provider_volume_member, provider_volume: volume, member_index: 0) }

    it 'returns formatted display name' do
      expect(member.display_name).to eq("#{volume.name} - Member 0")
    end
  end
end
