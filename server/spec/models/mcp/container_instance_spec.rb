# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mcp::ContainerInstance, type: :model do
  describe 'associations' do
    it { should belong_to(:account) }
    it { should belong_to(:template).class_name('Mcp::ContainerTemplate').optional }
    it { should belong_to(:triggered_by).class_name('User').optional }
    it { should belong_to(:a2a_task).class_name('Ai::A2aTask').optional }
  end

  describe 'validations' do
    subject { build(:mcp_container_instance) }

    it { should validate_inclusion_of(:status).in_array(%w[pending provisioning running completed failed cancelled timeout]) }
  end

  describe 'scopes' do
    let!(:pending_instance) { create(:mcp_container_instance, :pending) }
    let!(:running_instance) { create(:mcp_container_instance, :running) }
    let!(:completed_instance) { create(:mcp_container_instance, :completed) }
    let!(:failed_instance) { create(:mcp_container_instance, :failed) }

    describe '.active' do
      it 'returns pending, provisioning, and running instances' do
        expect(Mcp::ContainerInstance.active).to include(pending_instance, running_instance)
        expect(Mcp::ContainerInstance.active).not_to include(completed_instance, failed_instance)
      end
    end

    describe '.completed' do
      it 'returns only completed instances' do
        expect(Mcp::ContainerInstance.completed).to include(completed_instance)
        expect(Mcp::ContainerInstance.completed).not_to include(running_instance)
      end
    end

    describe '.failed' do
      it 'returns only failed instances' do
        expect(Mcp::ContainerInstance.failed).to include(failed_instance)
      end
    end
  end

  describe 'status methods' do
    describe '#pending?' do
      it 'returns true when pending' do
        instance = build(:mcp_container_instance, :pending)
        expect(instance.pending?).to be true
      end
    end

    describe '#running?' do
      it 'returns true when running' do
        instance = build(:mcp_container_instance, :running)
        expect(instance.running?).to be true
      end
    end

    describe '#finished?' do
      it 'returns true for completed instances' do
        instance = build(:mcp_container_instance, :completed)
        expect(instance.finished?).to be true
      end

      it 'returns true for failed instances' do
        instance = build(:mcp_container_instance, :failed)
        expect(instance.finished?).to be true
      end

      it 'returns false for running instances' do
        instance = build(:mcp_container_instance, :running)
        expect(instance.finished?).to be false
      end
    end
  end

  describe '#complete!' do
    let(:instance) { create(:mcp_container_instance, :running) }

    it 'changes status to completed' do
      instance.complete!(output: { result: 'success' }, exit_code: '0')
      expect(instance.reload.status).to eq('completed')
      expect(instance.output_data).to eq({ 'result' => 'success' })
    end

    it 'sets completed_at' do
      instance.complete!(output: {}, exit_code: '0')
      expect(instance.completed_at).to be_present
    end
  end

  describe '#fail!' do
    let(:instance) { create(:mcp_container_instance, :running) }

    it 'changes status to failed' do
      instance.fail!('Task execution error')
      expect(instance.reload.status).to eq('failed')
    end
  end

  describe '#cancel!' do
    let(:instance) { create(:mcp_container_instance, :running) }

    it 'changes status to cancelled' do
      instance.cancel!
      expect(instance.reload.status).to eq('cancelled')
    end
  end

  describe '#duration_ms' do
    let(:instance) { create(:mcp_container_instance, :completed) }

    it 'calculates execution duration' do
      expect(instance.duration_ms).to be_present
    end
  end

  describe '#record_resource_usage' do
    let(:instance) { create(:mcp_container_instance, :running) }

    it 'updates resource usage data' do
      instance.record_resource_usage(memory_mb: 256, cpu_millicores: 500)
      expect(instance.memory_used_mb).to eq(256)
    end
  end
end
