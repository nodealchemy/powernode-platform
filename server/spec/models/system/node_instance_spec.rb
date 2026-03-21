# frozen_string_literal: true

require 'rails_helper'

RSpec.describe System::NodeInstance, type: :model do
  let(:node) { create(:system_node) }

  describe 'constants' do
    it 'defines valid varieties' do
      expect(described_class::VARIETIES).to eq(%w[cloud physical dynamic])
    end

    it 'defines valid statuses' do
      expect(described_class::STATUSES).to eq(%w[pending provisioning starting running stopping stopped rebooting terminated error])
    end
  end

  describe 'associations' do
    it { is_expected.to belong_to(:node).class_name('System::Node') }
    it { is_expected.to belong_to(:provider_region).class_name('System::ProviderRegion').optional }
    it { is_expected.to belong_to(:provider_instance_type).class_name('System::ProviderInstanceType').optional }
    it { is_expected.to have_many(:instance_mount_points).class_name('System::InstanceMountPoint').dependent(:destroy) }
    it { is_expected.to have_many(:mount_points).through(:instance_mount_points) }
    it { is_expected.to have_many(:operations).class_name('System::Operation').dependent(:destroy) }
    it { is_expected.to have_many(:provider_volumes).class_name('System::ProviderVolume') }
  end

  describe 'validations' do
    subject { build(:system_node_instance, node: node) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:variety) }
    it { is_expected.to validate_presence_of(:status) }
    it { is_expected.to validate_inclusion_of(:variety).in_array(described_class::VARIETIES) }
    it { is_expected.to validate_inclusion_of(:status).in_array(described_class::STATUSES) }

    it 'validates uniqueness of name scoped to node' do
      instance = create(:system_node_instance, node: node, name: 'instance-1')
      duplicate = build(:system_node_instance, node: node, name: 'instance-1')

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:name]).to include('has already been taken')
    end

    it 'allows same name in different nodes' do
      other_node = create(:system_node)
      create(:system_node_instance, node: node, name: 'instance-1')
      other_instance = build(:system_node_instance, node: other_node, name: 'instance-1')

      expect(other_instance).to be_valid
    end
  end

  describe 'delegations' do
    let(:account) { node.account }
    let(:instance) { create(:system_node_instance, node: node) }

    it 'delegates account to node' do
      expect(instance.account).to eq(account)
    end

    it 'delegates account_id to node' do
      expect(instance.account_id).to eq(account.id)
    end
  end

  describe 'scopes' do
    let!(:cloud_instance) { create(:system_node_instance, node: node, variety: 'cloud') }
    let!(:physical_instance) { create(:system_node_instance, node: node, variety: 'physical') }
    let!(:dynamic_instance) { create(:system_node_instance, node: node, variety: 'dynamic') }
    let!(:pending_instance) { create(:system_node_instance, node: node, status: 'pending') }
    let!(:running_instance) { create(:system_node_instance, node: node, status: 'running') }
    let!(:stopped_instance) { create(:system_node_instance, node: node, status: 'stopped') }
    let!(:terminated_instance) { create(:system_node_instance, node: node, status: 'terminated') }
    let!(:error_instance) { create(:system_node_instance, node: node, status: 'error') }

    describe 'variety scopes' do
      it '.cloud returns only cloud instances' do
        expect(described_class.cloud).to include(cloud_instance)
        expect(described_class.cloud).not_to include(physical_instance, dynamic_instance)
      end

      it '.physical returns only physical instances' do
        expect(described_class.physical).to include(physical_instance)
        expect(described_class.physical).not_to include(cloud_instance, dynamic_instance)
      end

      it '.dynamic returns only dynamic instances' do
        expect(described_class.dynamic).to include(dynamic_instance)
        expect(described_class.dynamic).not_to include(cloud_instance, physical_instance)
      end
    end

    describe 'status scopes' do
      it '.pending returns only pending instances' do
        expect(described_class.pending).to include(pending_instance)
      end

      it '.running returns only running instances' do
        expect(described_class.running).to include(running_instance)
      end

      it '.stopped returns only stopped instances' do
        expect(described_class.stopped).to include(stopped_instance)
      end

      it '.terminated returns only terminated instances' do
        expect(described_class.terminated).to include(terminated_instance)
      end

      it '.errored returns only error instances' do
        expect(described_class.errored).to include(error_instance)
      end

      it '.active returns non-terminated and non-error instances' do
        active = described_class.active
        expect(active).to include(pending_instance, running_instance, stopped_instance)
        expect(active).not_to include(terminated_instance, error_instance)
      end
    end
  end

  describe 'status predicates' do
    let(:instance) { build(:system_node_instance, node: node) }

    described_class::STATUSES.each do |status|
      describe "##{status}?" do
        it "returns true when status is #{status}" do
          instance.status = status
          expect(instance.public_send("#{status}?")).to be true
        end

        it "returns false when status is not #{status}" do
          other_status = (described_class::STATUSES - [status]).first
          instance.status = other_status
          expect(instance.public_send("#{status}?")).to be false
        end
      end
    end
  end

  describe '#active?' do
    let(:instance) { build(:system_node_instance, node: node) }

    it 'returns true for running instances' do
      instance.status = 'running'
      expect(instance.active?).to be true
    end

    it 'returns true for pending instances' do
      instance.status = 'pending'
      expect(instance.active?).to be true
    end

    it 'returns false for terminated instances' do
      instance.status = 'terminated'
      expect(instance.active?).to be false
    end

    it 'returns false for error instances' do
      instance.status = 'error'
      expect(instance.active?).to be false
    end
  end

  describe 'control action predicates' do
    let(:instance) { build(:system_node_instance, node: node) }

    describe '#can_start?' do
      it 'returns true for stopped instances' do
        instance.status = 'stopped'
        expect(instance.can_start?).to be true
      end

      it 'returns true for error instances' do
        instance.status = 'error'
        expect(instance.can_start?).to be true
      end

      it 'returns false for running instances' do
        instance.status = 'running'
        expect(instance.can_start?).to be false
      end
    end

    describe '#can_stop?' do
      it 'returns true for running instances' do
        instance.status = 'running'
        expect(instance.can_stop?).to be true
      end

      it 'returns true for starting instances' do
        instance.status = 'starting'
        expect(instance.can_stop?).to be true
      end

      it 'returns false for stopped instances' do
        instance.status = 'stopped'
        expect(instance.can_stop?).to be false
      end
    end

    describe '#can_reboot?' do
      it 'returns true for running instances' do
        instance.status = 'running'
        expect(instance.can_reboot?).to be true
      end

      it 'returns false for stopped instances' do
        instance.status = 'stopped'
        expect(instance.can_reboot?).to be false
      end
    end

    describe '#can_terminate?' do
      it 'returns true for stopped instances' do
        instance.status = 'stopped'
        expect(instance.can_terminate?).to be true
      end

      it 'returns true for running instances' do
        instance.status = 'running'
        expect(instance.can_terminate?).to be true
      end

      it 'returns true for error instances' do
        instance.status = 'error'
        expect(instance.can_terminate?).to be true
      end

      it 'returns false for pending instances' do
        instance.status = 'pending'
        expect(instance.can_terminate?).to be false
      end
    end
  end

  describe 'encrypted attributes' do
    it 'has encrypted key attribute defined' do
      instance = build(:system_node_instance, node: node)
      expect(instance).to respond_to(:key)
      expect(instance).to respond_to(:key=)
    end
  end

  describe 'config accessor' do
    it 'allows storing and retrieving config data' do
      instance = create(:system_node_instance, node: node)
      instance.update!(config: { 'custom' => 'value', 'ip_info' => { 'internal' => '10.0.0.1' } })

      instance.reload
      expect(instance.config['custom']).to eq('value')
      expect(instance.config['ip_info']['internal']).to eq('10.0.0.1')
    end
  end
end
