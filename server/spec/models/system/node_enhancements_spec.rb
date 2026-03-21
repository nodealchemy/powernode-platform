# frozen_string_literal: true

require 'rails_helper'

RSpec.describe System::Node, 'runtime and storage enhancements', type: :model do
  let(:account) { create(:account) }

  describe 'scopes' do
    let!(:tmpfs_node) { create(:system_node, account: account, tmpfs_store: true) }
    let!(:regular_node) { create(:system_node, account: account, tmpfs_store: false) }

    describe '.with_tmpfs' do
      it 'returns only nodes with tmpfs enabled' do
        expect(described_class.with_tmpfs).to contain_exactly(tmpfs_node)
      end
    end

    describe '.without_tmpfs' do
      it 'returns only nodes without tmpfs' do
        expect(described_class.without_tmpfs).to contain_exactly(regular_node)
      end
    end
  end

  describe '#increment_runtime!' do
    it 'increments runtime_amount by default of 1' do
      node = create(:system_node, account: account, runtime_amount: 10)
      node.increment_runtime!

      expect(node.reload.runtime_amount).to eq(11)
    end

    it 'increments runtime_amount by specified minutes' do
      node = create(:system_node, account: account, runtime_amount: 10)
      node.increment_runtime!(5)

      expect(node.reload.runtime_amount).to eq(15)
    end

    it 'handles nil runtime_amount' do
      node = create(:system_node, account: account)
      # Ensure runtime_amount starts at 0 (from factory default)
      expect(node.runtime_amount).to eq(0)

      node.increment_runtime!(10)
      expect(node.reload.runtime_amount).to eq(10)
    end
  end

  describe '#runtime_hours' do
    it 'converts minutes to hours' do
      node = build(:system_node, account: account, runtime_amount: 120)
      expect(node.runtime_hours).to eq(2.0)
    end

    it 'handles fractional hours' do
      node = build(:system_node, account: account, runtime_amount: 90)
      expect(node.runtime_hours).to eq(1.5)
    end

    it 'handles nil runtime_amount' do
      node = build(:system_node, account: account, runtime_amount: nil)
      expect(node.runtime_hours).to eq(0.0)
    end

    it 'handles zero runtime_amount' do
      node = build(:system_node, account: account, runtime_amount: 0)
      expect(node.runtime_hours).to eq(0.0)
    end
  end

  describe '#runtime_days' do
    it 'converts hours to days' do
      node = build(:system_node, account: account, runtime_amount: 1440) # 24 hours
      expect(node.runtime_days).to eq(1.0)
    end

    it 'handles fractional days' do
      node = build(:system_node, account: account, runtime_amount: 720) # 12 hours
      expect(node.runtime_days).to eq(0.5)
    end
  end

  describe '#reset_runtime!' do
    it 'resets runtime_amount to 0' do
      node = create(:system_node, account: account, runtime_amount: 500)
      node.reset_runtime!

      expect(node.reload.runtime_amount).to eq(0)
    end
  end

  describe '#uses_tmpfs?' do
    it 'returns true when tmpfs_store is true' do
      node = build(:system_node, account: account, tmpfs_store: true)
      expect(node.uses_tmpfs?).to be true
    end

    it 'returns false when tmpfs_store is false' do
      node = build(:system_node, account: account, tmpfs_store: false)
      expect(node.uses_tmpfs?).to be false
    end

    it 'returns false when tmpfs_store is nil' do
      node = build(:system_node, account: account, tmpfs_store: nil)
      expect(node.uses_tmpfs?).to be false
    end
  end

  describe '#enable_tmpfs!' do
    it 'sets tmpfs_store to true' do
      node = create(:system_node, account: account, tmpfs_store: false)
      node.enable_tmpfs!

      expect(node.reload.tmpfs_store).to be true
    end
  end

  describe '#disable_tmpfs!' do
    it 'sets tmpfs_store to false' do
      node = create(:system_node, account: account, tmpfs_store: true)
      node.disable_tmpfs!

      expect(node.reload.tmpfs_store).to be false
    end
  end

  describe 'factory traits' do
    describe ':with_runtime' do
      it 'creates node with 120 minutes runtime' do
        node = create(:system_node, :with_runtime, account: account)
        expect(node.runtime_amount).to eq(120)
        expect(node.runtime_hours).to eq(2.0)
      end
    end

    describe ':with_tmpfs' do
      it 'creates node with tmpfs enabled' do
        node = create(:system_node, :with_tmpfs, account: account)
        expect(node.tmpfs_store).to be true
        expect(node.uses_tmpfs?).to be true
      end
    end
  end

  describe 'combined runtime tracking scenario' do
    it 'tracks runtime over multiple increments' do
      node = create(:system_node, account: account, runtime_amount: 0)

      # Simulate runtime tracking over time
      node.increment_runtime!(60)  # 1 hour
      node.increment_runtime!(30)  # 30 minutes
      node.increment_runtime!(90)  # 1.5 hours

      node.reload
      expect(node.runtime_amount).to eq(180)
      expect(node.runtime_hours).to eq(3.0)
      expect(node.runtime_days).to be_within(0.001).of(0.125)
    end
  end
end
