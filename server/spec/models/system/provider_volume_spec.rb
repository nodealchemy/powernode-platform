# frozen_string_literal: true

require 'rails_helper'

RSpec.describe System::ProviderVolume, type: :model do
  let(:account) { create(:account) }
  let(:node) { create(:system_node) }
  let(:instance) { create(:system_node_instance, node: node) }

  describe 'constants' do
    it 'defines valid statuses' do
      expect(described_class::STATUSES).to eq(%w[creating available in-use deleting deleted error])
    end
  end

  describe 'associations' do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:volume_type).class_name('System::ProviderVolumeType').optional }
    it { is_expected.to belong_to(:provider_region).class_name('System::ProviderRegion').optional }
    it { is_expected.to belong_to(:availability_zone).class_name('System::ProviderAvailabilityZone').optional }
    it { is_expected.to belong_to(:node_instance).class_name('System::NodeInstance').optional }
    it { is_expected.to have_many(:snapshots).class_name('System::ProviderVolumeSnapshot').dependent(:restrict_with_error) }
    it { is_expected.to have_many(:operations).class_name('System::Operation').dependent(:destroy) }
  end

  describe 'validations' do
    subject { build(:system_provider_volume, account: account) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:size_gb) }
    it { is_expected.to validate_presence_of(:status) }
    it { is_expected.to validate_inclusion_of(:status).in_array(described_class::STATUSES) }
    it { is_expected.to validate_numericality_of(:size_gb).only_integer.is_greater_than(0) }
    it { is_expected.to validate_numericality_of(:iops).only_integer.is_greater_than(0).allow_nil }
    it { is_expected.to validate_numericality_of(:throughput).only_integer.is_greater_than(0).allow_nil }

    it 'validates uniqueness of name scoped to account (case insensitive)' do
      create(:system_provider_volume, account: account, name: 'TestVolume')
      duplicate = build(:system_provider_volume, account: account, name: 'testvolume')

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:name]).to include('has already been taken')
    end
  end

  describe 'scopes' do
    let!(:creating_volume) { create(:system_provider_volume, account: account, status: 'creating') }
    let!(:available_volume) { create(:system_provider_volume, account: account, status: 'available') }
    let!(:in_use_volume) { create(:system_provider_volume, account: account, status: 'in-use', node_instance: instance) }
    let!(:deleting_volume) { create(:system_provider_volume, account: account, status: 'deleting') }
    let!(:error_volume) { create(:system_provider_volume, account: account, status: 'error') }
    let!(:encrypted_volume) { create(:system_provider_volume, account: account, encrypted: true) }
    let!(:unencrypted_volume) { create(:system_provider_volume, account: account, encrypted: false) }

    describe 'status scopes' do
      it '.creating returns only creating volumes' do
        expect(described_class.creating).to include(creating_volume)
        expect(described_class.creating).not_to include(available_volume)
      end

      it '.available returns only available volumes' do
        expect(described_class.available).to include(available_volume)
      end

      it '.in_use returns only in-use volumes' do
        expect(described_class.in_use).to include(in_use_volume)
      end

      it '.deleting returns only deleting volumes' do
        expect(described_class.deleting).to include(deleting_volume)
      end

      it '.errored returns only error volumes' do
        expect(described_class.errored).to include(error_volume)
      end
    end

    describe '.attached' do
      it 'returns volumes attached to an instance' do
        expect(described_class.attached).to include(in_use_volume)
        expect(described_class.attached).not_to include(available_volume)
      end
    end

    describe '.unattached' do
      it 'returns volumes not attached to an instance' do
        expect(described_class.unattached).to include(available_volume)
        expect(described_class.unattached).not_to include(in_use_volume)
      end
    end

    describe '.encrypted_volumes' do
      it 'returns only encrypted volumes' do
        expect(described_class.encrypted_volumes).to include(encrypted_volume)
        expect(described_class.encrypted_volumes).not_to include(unencrypted_volume)
      end
    end

    describe '.unencrypted_volumes' do
      it 'returns only unencrypted volumes' do
        expect(described_class.unencrypted_volumes).to include(unencrypted_volume)
        expect(described_class.unencrypted_volumes).not_to include(encrypted_volume)
      end
    end
  end

  describe 'status predicates' do
    let(:volume) { build(:system_provider_volume, account: account) }

    it 'creating? returns true when status is creating' do
      volume.status = 'creating'
      expect(volume.creating?).to be true
    end

    it 'available? returns true when status is available' do
      volume.status = 'available'
      expect(volume.available?).to be true
    end

    it 'in_use? returns true when status is in-use' do
      volume.status = 'in-use'
      expect(volume.in_use?).to be true
    end

    it 'error? returns true when status is error' do
      volume.status = 'error'
      expect(volume.error?).to be true
    end
  end

  describe '#attached?' do
    let(:volume) { build(:system_provider_volume, account: account) }

    it 'returns true when node_instance_id is present' do
      volume.node_instance = instance
      expect(volume.attached?).to be true
    end

    it 'returns false when node_instance_id is nil' do
      volume.node_instance = nil
      expect(volume.attached?).to be false
    end
  end

  describe 'action predicates' do
    let(:volume) { build(:system_provider_volume, account: account) }

    describe '#can_attach?' do
      it 'returns true for available unattached volumes' do
        volume.status = 'available'
        volume.node_instance = nil
        expect(volume.can_attach?).to be true
      end

      it 'returns false for attached volumes' do
        volume.status = 'available'
        volume.node_instance = instance
        expect(volume.can_attach?).to be false
      end

      it 'returns false for non-available volumes' do
        volume.status = 'creating'
        expect(volume.can_attach?).to be false
      end
    end

    describe '#can_detach?' do
      it 'returns true for in-use attached volumes' do
        volume.status = 'in-use'
        volume.node_instance = instance
        expect(volume.can_detach?).to be true
      end

      it 'returns false for unattached volumes' do
        volume.status = 'available'
        volume.node_instance = nil
        expect(volume.can_detach?).to be false
      end
    end

    describe '#can_delete?' do
      it 'returns true for available unattached volumes' do
        volume.status = 'available'
        volume.node_instance = nil
        expect(volume.can_delete?).to be true
      end

      it 'returns true for error unattached volumes' do
        volume.status = 'error'
        volume.node_instance = nil
        expect(volume.can_delete?).to be true
      end

      it 'returns false for attached volumes' do
        volume.status = 'available'
        volume.node_instance = instance
        expect(volume.can_delete?).to be false
      end

      it 'returns false for in-use volumes' do
        volume.status = 'in-use'
        expect(volume.can_delete?).to be false
      end
    end

    describe '#can_snapshot?' do
      it 'returns true for available volumes' do
        volume.status = 'available'
        expect(volume.can_snapshot?).to be true
      end

      it 'returns true for in-use volumes' do
        volume.status = 'in-use'
        expect(volume.can_snapshot?).to be true
      end

      it 'returns false for creating volumes' do
        volume.status = 'creating'
        expect(volume.can_snapshot?).to be false
      end
    end
  end

  describe '#attach_to!' do
    let(:volume) { create(:system_provider_volume, account: account, status: 'available') }

    it 'attaches volume to instance' do
      result = volume.attach_to!(instance, '/dev/sdb')

      expect(result).to be true
      expect(volume.node_instance).to eq(instance)
      expect(volume.device_name).to eq('/dev/sdb')
      expect(volume.status).to eq('in-use')
    end

    it 'returns false if volume cannot be attached' do
      volume.update!(status: 'in-use', node_instance: instance)

      result = volume.attach_to!(instance)
      expect(result).to be false
    end
  end

  describe '#detach!' do
    let(:volume) do
      create(:system_provider_volume,
             account: account,
             status: 'in-use',
             node_instance: instance,
             device_name: '/dev/sdb')
    end

    it 'detaches volume from instance' do
      result = volume.detach!

      expect(result).to be true
      expect(volume.node_instance).to be_nil
      expect(volume.device_name).to be_nil
      expect(volume.status).to eq('available')
    end

    it 'returns false if volume cannot be detached' do
      volume.update!(status: 'available', node_instance: nil)

      result = volume.detach!
      expect(result).to be false
    end
  end

  describe '#snapshot_count' do
    let(:volume) { create(:system_provider_volume, account: account) }

    it 'returns the number of snapshots' do
      create_list(:system_provider_volume_snapshot, 3, volume: volume)
      expect(volume.snapshot_count).to eq(3)
    end
  end

  describe '#provider' do
    let(:provider) { create(:system_provider, account: account) }
    let(:region) { create(:system_provider_region, provider: provider) }
    let(:volume_type) { create(:system_provider_volume_type, provider: provider) }

    it 'returns provider from volume_type' do
      volume = create(:system_provider_volume, account: account, volume_type: volume_type)
      expect(volume.provider).to eq(provider)
    end

    it 'returns provider from provider_region when volume_type is nil' do
      volume = create(:system_provider_volume, account: account, provider_region: region, volume_type: nil)
      expect(volume.provider).to eq(provider)
    end

    it 'returns nil when neither is set' do
      volume = create(:system_provider_volume, account: account, volume_type: nil, provider_region: nil)
      expect(volume.provider).to be_nil
    end
  end

  describe 'cascading restrictions' do
    let(:volume) { create(:system_provider_volume, account: account) }

    it 'prevents deletion when snapshots exist' do
      create(:system_provider_volume_snapshot, volume: volume)

      expect { volume.destroy }.not_to change(described_class, :count)
      expect(volume.errors[:base]).to include(/Cannot delete record/)
    end
  end
end
