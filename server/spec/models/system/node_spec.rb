# frozen_string_literal: true

require 'rails_helper'

RSpec.describe System::Node, type: :model do
  # Create an account factory if not exists
  let(:account) { create(:account) }
  let(:node_template) { create(:system_node_template) }

  describe 'associations' do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:node_template).class_name('System::NodeTemplate') }
    it { is_expected.to belong_to(:worker).optional }
    it { is_expected.to have_many(:node_instances).class_name('System::NodeInstance').dependent(:destroy) }
    it { is_expected.to have_many(:node_module_assignments).class_name('System::NodeModuleAssignment').dependent(:destroy) }
    it { is_expected.to have_many(:node_modules).through(:node_module_assignments) }
    it { is_expected.to have_many(:operations).class_name('System::Operation').dependent(:destroy) }
  end

  describe 'validations' do
    subject { build(:system_node) }

    it { is_expected.to validate_presence_of(:name) }

    it 'validates uniqueness of name scoped to account' do
      node = create(:system_node, account: account, name: 'test-node')
      duplicate = build(:system_node, account: account, name: 'test-node')

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:name]).to include('has already been taken')
    end

    it 'allows same name in different accounts' do
      other_account = create(:account)
      create(:system_node, account: account, name: 'test-node')
      other_node = build(:system_node, account: other_account, name: 'test-node')

      expect(other_node).to be_valid
    end
  end

  describe 'encrypted attributes' do
    it 'has encrypted ssh_key attribute defined' do
      node = build(:system_node)
      expect(node).to respond_to(:ssh_key)
      expect(node).to respond_to(:ssh_key=)
    end

    it 'has encrypted ssh_host_key attribute defined' do
      node = build(:system_node)
      expect(node).to respond_to(:ssh_host_key)
      expect(node).to respond_to(:ssh_host_key=)
    end
  end

  describe 'scopes' do
    let!(:worker) { create(:worker, worker_type: 'infrastructure') }
    let!(:node_with_worker) { create(:system_node, worker: worker) }
    let!(:node_without_worker) { create(:system_node, worker: nil) }
    let!(:node_with_public_ip) { create(:system_node, allocate_public_ip: true) }
    let!(:node_without_public_ip) { create(:system_node, allocate_public_ip: false) }

    describe '.with_worker' do
      it 'returns nodes with a worker assigned' do
        expect(described_class.with_worker).to include(node_with_worker)
        expect(described_class.with_worker).not_to include(node_without_worker)
      end
    end

    describe '.without_worker' do
      it 'returns nodes without a worker assigned' do
        expect(described_class.without_worker).to include(node_without_worker)
        expect(described_class.without_worker).not_to include(node_with_worker)
      end
    end

    describe '.with_public_ip' do
      it 'returns nodes with public IP allocation enabled' do
        expect(described_class.with_public_ip).to include(node_with_public_ip)
        expect(described_class.with_public_ip).not_to include(node_without_public_ip)
      end
    end
  end

  describe 'config accessor' do
    it 'allows storing and retrieving config data' do
      node = create(:system_node)
      node.update!(config: { 'custom_setting' => 'value', 'nested' => { 'key' => 123 } })

      node.reload
      expect(node.config['custom_setting']).to eq('value')
      expect(node.config['nested']['key']).to eq(123)
    end
  end

  describe 'instance management' do
    let(:node) { create(:system_node) }

    it 'destroys associated instances when destroyed' do
      instance = create(:system_node_instance, node: node)

      expect { node.destroy }.to change(System::NodeInstance, :count).by(-1)
      expect { instance.reload }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe 'module assignments' do
    let(:node) { create(:system_node) }
    let(:node_module) { create(:system_node_module) }

    it 'can have modules assigned through assignments' do
      assignment = create(:system_node_module_assignment, node: node, node_module: node_module)

      expect(node.node_modules).to include(node_module)
      expect(node.node_module_assignments).to include(assignment)
    end

    it 'destroys assignments when node is destroyed' do
      create(:system_node_module_assignment, node: node, node_module: node_module)

      expect { node.destroy }.to change(System::NodeModuleAssignment, :count).by(-1)
    end
  end
end
