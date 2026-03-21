# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Volume Management Integration', type: :integration do
  let(:account) { create(:account) }
  let(:node) { create(:system_node, account: account) }
  let(:instance) { create(:system_node_instance, :running, node: node) }

  describe 'single volume lifecycle' do
    let(:volume) { create(:system_provider_volume, account: account, size_gb: 100, status: 'available') }

    it 'tracks volume through complete lifecycle' do
      # Initial state
      expect(volume.available?).to be true
      expect(volume.can_attach?).to be true

      # Attach to instance
      result = volume.attach_to!(instance, '/dev/sdb')
      expect(result).to be true
      expect(volume.reload.in_use?).to be true
      expect(volume.attached?).to be true
      expect(volume.node_instance).to eq(instance)

      # Cannot attach again while in use
      expect(volume.can_attach?).to be false

      # Can detach
      expect(volume.can_detach?).to be true
      result = volume.detach!
      expect(result).to be true
      expect(volume.reload.available?).to be true
      expect(volume.attached?).to be false

      # Can delete when available
      expect(volume.can_delete?).to be true
    end

    it 'prevents deletion when attached' do
      volume.attach_to!(instance, '/dev/sdb')

      expect(volume.can_delete?).to be false
    end

    it 'allows snapshotting of available volumes' do
      expect(volume.can_snapshot?).to be true

      snapshot = create(:system_provider_volume_snapshot, account: account, volume: volume)
      expect(volume.snapshot_count).to eq(1)
    end

    it 'allows snapshotting of in-use volumes' do
      volume.attach_to!(instance, '/dev/sdb')

      expect(volume.can_snapshot?).to be true
    end
  end

  describe 'RAID volume management' do
    describe 'RAID 0 (striping)' do
      let(:raid_volume) do
        create(:system_provider_volume, account: account, size_gb: 100, raid_level: 0, status: 'creating')
      end

      it 'manages RAID 0 volume with multiple members' do
        # Add members to RAID array (they start as 'pending')
        member1 = raid_volume.add_member!(size_gb: 100, device_name: '/dev/sdb')
        member2 = raid_volume.add_member!(size_gb: 100, device_name: '/dev/sdc')

        expect(raid_volume.raid?).to be true
        expect(raid_volume.total_member_count).to eq(2)

        # Both start as pending, so not in active count
        expect(member1.status).to eq('pending')
        expect(member2.status).to eq('pending')

        # Members become available
        member1.update!(status: 'available')
        member2.update!(status: 'available')

        raid_volume.reload
        expect(raid_volume.active_member_count).to eq(2)
        expect(raid_volume.all_members_ready?).to be true
        expect(raid_volume.has_minimum_members?).to be true

        # RAID 0 doubles effective capacity
        expect(raid_volume.raid_capacity).to eq(200) # 100 × 2
      end

      it 'requires minimum 2 members' do
        raid_volume.add_member!(size_gb: 100, device_name: '/dev/sdb')

        expect(raid_volume.has_minimum_members?).to be false
      end
    end

    describe 'RAID 1 (mirroring)' do
      let(:raid_volume) do
        create(:system_provider_volume, account: account, size_gb: 100, raid_level: 1, status: 'creating')
      end

      it 'manages RAID 1 volume with mirrored members' do
        member1 = raid_volume.add_member!(size_gb: 100, device_name: '/dev/sdb')
        member2 = raid_volume.add_member!(size_gb: 100, device_name: '/dev/sdc')

        member1.update!(status: 'available')
        member2.update!(status: 'available')

        raid_volume.reload

        # RAID 1 maintains original capacity (mirroring)
        expect(raid_volume.raid_capacity).to eq(100)
        expect(raid_volume.active_member_count).to eq(2)
      end
    end

    describe 'RAID member management' do
      let(:raid_volume) { create(:system_provider_volume, :raid0, account: account) }

      it 'maintains member index uniqueness' do
        existing_member = raid_volume.volume_members.first
        expect(existing_member.member_index).to be_present

        # Add new member with auto-incrementing index
        new_member = raid_volume.add_member!(size_gb: 100, device_name: '/dev/sdd')
        expect(new_member.member_index).to be > existing_member.member_index
      end

      it 'tracks member status transitions' do
        member = raid_volume.volume_members.first

        # Initial status from factory
        expect(member.available?).to be true
        expect(member.ready?).to be true

        # Transition to attached
        member.update!(status: 'attached')
        expect(member.attached?).to be true
        expect(member.ready?).to be true
        expect(member.can_delete?).to be false

        # Cannot delete while attached
        expect(member.can_delete?).to be false
      end

      it 'excludes deleted/error members from active count' do
        raid_volume.volume_members.first.update!(status: 'deleted')

        expect(raid_volume.active_member_count).to eq(1)
        expect(raid_volume.has_minimum_members?).to be false
      end

      it 'destroys members when volume is destroyed' do
        member_ids = raid_volume.volume_members.pluck(:id)
        expect(member_ids).not_to be_empty

        raid_volume.destroy!

        expect(System::ProviderVolumeMember.where(id: member_ids)).to be_empty
      end
    end
  end

  describe 'volume status transitions' do
    let(:volume) { create(:system_provider_volume, account: account, status: 'creating') }

    it 'tracks creating -> available transition' do
      expect(volume.creating?).to be true

      volume.update!(status: 'available')
      expect(volume.available?).to be true
      expect(volume.can_attach?).to be true
    end

    it 'tracks available -> in-use transition via attach' do
      volume.update!(status: 'available')
      volume.attach_to!(instance, '/dev/sdb')

      expect(volume.in_use?).to be true
    end

    it 'handles error state' do
      volume.update!(status: 'error')

      expect(volume.error?).to be true
      expect(volume.can_delete?).to be true
      expect(volume.can_attach?).to be false
      expect(volume.can_snapshot?).to be false
    end

    it 'handles deleting state' do
      volume.update!(status: 'deleting')

      expect(volume.deleting?).to be true
      expect(volume.can_delete?).to be false
    end
  end

  describe 'volume scopes' do
    let!(:available_vol) { create(:system_provider_volume, account: account, status: 'available') }
    let!(:in_use_vol) { create(:system_provider_volume, account: account, status: 'in-use', node_instance: instance) }
    let!(:creating_vol) { create(:system_provider_volume, account: account, status: 'creating') }
    let!(:error_vol) { create(:system_provider_volume, account: account, status: 'error') }
    let!(:encrypted_vol) { create(:system_provider_volume, account: account, status: 'available', encrypted: true) }

    it 'filters by status' do
      expect(System::ProviderVolume.available).to include(available_vol, encrypted_vol)
      expect(System::ProviderVolume.in_use).to contain_exactly(in_use_vol)
      expect(System::ProviderVolume.creating).to contain_exactly(creating_vol)
      expect(System::ProviderVolume.errored).to contain_exactly(error_vol)
    end

    it 'filters by attachment' do
      expect(System::ProviderVolume.attached).to contain_exactly(in_use_vol)
      expect(System::ProviderVolume.unattached).to include(available_vol, creating_vol)
    end

    it 'filters by encryption' do
      expect(System::ProviderVolume.encrypted_volumes).to contain_exactly(encrypted_vol)
      expect(System::ProviderVolume.unencrypted_volumes).to include(available_vol, in_use_vol)
    end
  end

  describe 'snapshot management' do
    let(:volume) { create(:system_provider_volume, account: account, size_gb: 100) }

    it 'creates and tracks snapshots' do
      snapshot1 = create(:system_provider_volume_snapshot, account: account, volume: volume, name: 'Backup 1')
      snapshot2 = create(:system_provider_volume_snapshot, account: account, volume: volume, name: 'Backup 2')

      expect(volume.snapshots.count).to eq(2)
      expect(volume.snapshot_count).to eq(2)
    end

    it 'prevents volume deletion with snapshots' do
      create(:system_provider_volume_snapshot, account: account, volume: volume)

      # Volume has dependent snapshots - restrict_with_error prevents deletion
      expect { volume.destroy! }.to raise_error(ActiveRecord::RecordNotDestroyed)
    end
  end
end
