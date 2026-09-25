# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Devops::ContainerInstance, type: :model do
  describe 'associations' do
    it { should belong_to(:account) }
    it { should belong_to(:template).class_name('Devops::ContainerTemplate').optional }
    it { should belong_to(:triggered_by).class_name('User').optional }
    it { should belong_to(:a2a_task).class_name('Ai::A2aTask').optional }
  end

  describe 'validations' do
    subject { build(:devops_container_instance) }

    it { should validate_inclusion_of(:status).in_array(%w[pending provisioning running paused completed failed cancelled timeout]) }
  end

  describe 'scopes' do
    let!(:pending_instance) { create(:devops_container_instance, :pending) }
    let!(:running_instance) { create(:devops_container_instance, :running) }
    let!(:completed_instance) { create(:devops_container_instance, :completed) }
    let!(:failed_instance) { create(:devops_container_instance, :failed) }

    describe '.active' do
      it 'returns pending, provisioning, and running instances' do
        expect(Devops::ContainerInstance.active).to include(pending_instance, running_instance)
        expect(Devops::ContainerInstance.active).not_to include(completed_instance, failed_instance)
      end
    end

    describe '.completed' do
      it 'returns only completed instances' do
        expect(Devops::ContainerInstance.completed).to include(completed_instance)
        expect(Devops::ContainerInstance.completed).not_to include(running_instance)
      end
    end

    describe '.failed' do
      it 'returns only failed instances' do
        expect(Devops::ContainerInstance.failed).to include(failed_instance)
      end
    end

    describe '.paused' do
      let!(:paused_instance) { create(:devops_container_instance, :paused) }

      it 'returns only paused instances' do
        expect(Devops::ContainerInstance.paused).to include(paused_instance)
        expect(Devops::ContainerInstance.paused).not_to include(running_instance, completed_instance)
      end
    end

    describe '.sandboxes' do
      let!(:sandbox_instance) { create(:devops_container_instance, :sandbox) }

      it 'returns only instances flagged as a sandbox in input_parameters' do
        expect(Devops::ContainerInstance.sandboxes).to include(sandbox_instance)
        expect(Devops::ContainerInstance.sandboxes).not_to include(pending_instance, running_instance)
      end
    end
  end

  describe 'status methods' do
    describe '#pending?' do
      it 'returns true when pending' do
        instance = build(:devops_container_instance, :pending)
        expect(instance.pending?).to be true
      end
    end

    describe '#running?' do
      it 'returns true when running' do
        instance = build(:devops_container_instance, :running)
        expect(instance.running?).to be true
      end
    end

    describe '#paused?' do
      it 'returns true when paused' do
        instance = build(:devops_container_instance, :paused)
        expect(instance.paused?).to be true
      end

      it 'returns false otherwise' do
        instance = build(:devops_container_instance, :running)
        expect(instance.paused?).to be false
      end
    end

    describe '#sandbox?' do
      it 'returns true when input_parameters flags sandbox_mode' do
        instance = build(:devops_container_instance, :sandbox)
        expect(instance.sandbox?).to be true
      end

      it 'returns false for a plain template execution' do
        instance = build(:devops_container_instance)
        expect(instance.sandbox?).to be false
      end

      it 'agrees with the .sandboxes scope on a string "true" (the JSONB ->> operator does not distinguish it from a boolean)' do
        instance = create(:devops_container_instance, input_parameters: { "sandbox_mode" => "true" })

        expect(instance.sandbox?).to be true
        expect(Devops::ContainerInstance.sandboxes).to include(instance)
      end
    end

    describe '#finished?' do
      it 'returns true for completed instances' do
        instance = build(:devops_container_instance, :completed)
        expect(instance.finished?).to be true
      end

      it 'returns true for failed instances' do
        instance = build(:devops_container_instance, :failed)
        expect(instance.finished?).to be true
      end

      it 'returns false for running instances' do
        instance = build(:devops_container_instance, :running)
        expect(instance.finished?).to be false
      end
    end
  end

  describe '#complete!' do
    let(:instance) { create(:devops_container_instance, :running) }

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
    let(:instance) { create(:devops_container_instance, :running) }

    it 'changes status to failed' do
      instance.fail!('Task execution error')
      expect(instance.reload.status).to eq('failed')
    end
  end

  describe '#cancel!' do
    let(:instance) { create(:devops_container_instance, :running) }

    it 'changes status to cancelled' do
      instance.cancel!
      expect(instance.reload.status).to eq('cancelled')
    end
  end

  describe '#duration_ms' do
    let(:instance) { create(:devops_container_instance, :completed) }

    it 'calculates execution duration' do
      expect(instance.duration_ms).to be_present
    end
  end

  describe '#instance_summary' do
    it 'flags a sandbox instance so list views can filter on it' do
      instance = create(:devops_container_instance, :sandbox)
      expect(instance.instance_summary[:sandbox]).to be true
    end

    it 'flags a plain template execution as not a sandbox' do
      instance = create(:devops_container_instance)
      expect(instance.instance_summary[:sandbox]).to be false
    end

    it 'carries the agent name and resource usage — cheap on the already-loaded row, no extra query' do
      instance = create(:devops_container_instance, :sandbox, :completed,
                         input_parameters: { "agent_id" => SecureRandom.uuid, "agent_name" => "My Agent", "sandbox_mode" => true })

      summary = instance.instance_summary

      expect(summary[:agent_name]).to eq("My Agent")
      expect(summary[:memory_used_mb]).to eq(instance.memory_used_mb)
      expect(summary[:cpu_used_millicores]).to eq(instance.cpu_used_millicores)
    end

    it 'is nil for a plain template execution with no agent' do
      instance = create(:devops_container_instance)
      expect(instance.instance_summary[:agent_name]).to be_nil
    end
  end

  describe '#record_resource_usage' do
    let(:instance) { create(:devops_container_instance, :running) }

    it 'updates resource usage data' do
      instance.record_resource_usage(memory_mb: 256, cpu_millicores: 500)
      expect(instance.memory_used_mb).to eq(256)
    end
  end
end
