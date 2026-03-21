# frozen_string_literal: true

require 'rails_helper'

RSpec.describe System::ProviderVolume, 'RAID functionality', type: :model do
  let(:account) { create(:account) }

  describe 'RAID constants' do
    it 'defines valid RAID levels' do
      expect(System::ProviderVolume::RAID_LEVELS).to eq([0, 1])
    end
  end

  describe 'validations' do
    it 'accepts valid RAID levels' do
      volume = build(:system_provider_volume, account: account, raid_level: 0)
      expect(volume).to be_valid

      volume.raid_level = 1
      expect(volume).to be_valid
    end

    it 'allows nil RAID level' do
      volume = build(:system_provider_volume, account: account, raid_level: nil)
      expect(volume).to be_valid
    end

    it 'rejects invalid RAID levels' do
      volume = build(:system_provider_volume, account: account, raid_level: 5)
      expect(volume).not_to be_valid
      expect(volume.errors[:raid_level]).to include('is not included in the list')
    end
  end

  describe '#raid?' do
    it 'returns true when raid_level is set' do
      volume = build(:system_provider_volume, account: account, raid_level: 0)
      expect(volume.raid?).to be true
    end

    it 'returns false when raid_level is nil' do
      volume = build(:system_provider_volume, account: account, raid_level: nil)
      expect(volume.raid?).to be false
    end
  end

  describe '#raid_capacity' do
    context 'with no RAID' do
      it 'returns size_gb' do
        volume = create(:system_provider_volume, account: account, size_gb: 100, raid_level: nil)
        expect(volume.raid_capacity).to eq(100)
      end
    end

    context 'with RAID 0 (striping)' do
      it 'returns size_gb multiplied by member count' do
        volume = create(:system_provider_volume, :raid0, account: account, size_gb: 100)
        expect(volume.raid_capacity).to eq(200) # 100 × 2 members
      end
    end

    context 'with RAID 1 (mirroring)' do
      it 'returns size_gb (no multiplication)' do
        volume = create(:system_provider_volume, :raid1, account: account, size_gb: 100)
        expect(volume.raid_capacity).to eq(100)
      end
    end
  end

  describe '#active_member_count' do
    context 'with no RAID' do
      it 'returns 1' do
        volume = create(:system_provider_volume, account: account, raid_level: nil)
        expect(volume.active_member_count).to eq(1)
      end
    end

    context 'with RAID' do
      it 'returns count of active members' do
        volume = create(:system_provider_volume, :raid0, account: account)
        expect(volume.active_member_count).to eq(2)
      end

      it 'excludes deleted and error members' do
        volume = create(:system_provider_volume, account: account, raid_level: 0)
        create(:system_provider_volume_member, provider_volume: volume, status: 'available', member_index: 0)
        create(:system_provider_volume_member, provider_volume: volume, status: 'deleted', member_index: 1)
        create(:system_provider_volume_member, provider_volume: volume, status: 'error', member_index: 2)

        expect(volume.active_member_count).to eq(1)
      end
    end
  end

  describe '#total_member_count' do
    it 'returns total count of all members' do
      volume = create(:system_provider_volume, account: account, raid_level: 0)
      create(:system_provider_volume_member, provider_volume: volume, status: 'available', member_index: 0)
      create(:system_provider_volume_member, provider_volume: volume, status: 'deleted', member_index: 1)

      expect(volume.total_member_count).to eq(2)
    end
  end

  describe '#all_members_ready?' do
    context 'with no RAID' do
      it 'returns true' do
        volume = create(:system_provider_volume, account: account, raid_level: nil)
        expect(volume.all_members_ready?).to be true
      end
    end

    context 'with RAID' do
      it 'returns true when all active members are ready' do
        volume = create(:system_provider_volume, :raid0, account: account)
        # The :raid0 trait creates 2 available members
        expect(volume.all_members_ready?).to be true
      end

      it 'returns false when some active members are not ready' do
        volume = create(:system_provider_volume, account: account, raid_level: 0)
        create(:system_provider_volume_member, provider_volume: volume, status: 'available', member_index: 0)
        create(:system_provider_volume_member, provider_volume: volume, status: 'pending', member_index: 1)

        expect(volume.all_members_ready?).to be false
      end
    end
  end

  describe '#add_member!' do
    context 'with no RAID' do
      it 'returns false' do
        volume = create(:system_provider_volume, account: account, raid_level: nil)
        expect(volume.add_member!(size_gb: 100)).to be false
      end
    end

    context 'with RAID' do
      it 'creates a new member with correct index' do
        volume = create(:system_provider_volume, account: account, raid_level: 0)
        create(:system_provider_volume_member, provider_volume: volume, status: 'available', member_index: 0)

        new_member = volume.add_member!(size_gb: 100, device_name: '/dev/sdc')

        expect(new_member).to be_persisted
        expect(new_member.member_index).to eq(1)
        expect(new_member.size_gb).to eq(100)
        expect(new_member.device_name).to eq('/dev/sdc')
        expect(new_member.status).to eq('pending')
      end

      it 'creates first member with index 0' do
        volume = create(:system_provider_volume, account: account, raid_level: 0)

        new_member = volume.add_member!(size_gb: 100)

        # First member gets index 0 when no members exist
        expect(new_member.member_index).to eq(0)
        expect(new_member).to be_persisted
      end
    end
  end

  describe '#minimum_members_for_raid' do
    it 'returns 2 for RAID 0' do
      volume = build(:system_provider_volume, account: account, raid_level: 0)
      expect(volume.minimum_members_for_raid).to eq(2)
    end

    it 'returns 2 for RAID 1' do
      volume = build(:system_provider_volume, account: account, raid_level: 1)
      expect(volume.minimum_members_for_raid).to eq(2)
    end
  end

  describe '#has_minimum_members?' do
    context 'with no RAID' do
      it 'returns true' do
        volume = create(:system_provider_volume, account: account, raid_level: nil)
        expect(volume.has_minimum_members?).to be true
      end
    end

    context 'with RAID' do
      it 'returns true when has minimum members' do
        volume = create(:system_provider_volume, :raid0, account: account)
        expect(volume.has_minimum_members?).to be true
      end

      it 'returns false when below minimum' do
        volume = create(:system_provider_volume, account: account, raid_level: 0)
        create(:system_provider_volume_member, provider_volume: volume, status: 'available', member_index: 0)

        expect(volume.has_minimum_members?).to be false
      end
    end
  end

  describe 'volume_members association' do
    it 'has many volume_members' do
      volume = create(:system_provider_volume, :raid0, account: account)
      expect(volume.volume_members.count).to eq(2)
    end

    it 'destroys members when volume is destroyed' do
      volume = create(:system_provider_volume, :raid0, account: account)
      member_ids = volume.volume_members.pluck(:id)

      volume.destroy

      expect(System::ProviderVolumeMember.where(id: member_ids)).to be_empty
    end
  end
end
