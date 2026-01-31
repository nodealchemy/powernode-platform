# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::A2aTask, type: :model do
  describe 'associations' do
    it { should belong_to(:account) }
    it { should belong_to(:from_agent).class_name('Ai::Agent').optional }
    it { should belong_to(:to_agent).class_name('Ai::Agent').optional }
    it { should belong_to(:workflow_run).class_name('Ai::WorkflowRun').optional }
    it { should have_many(:events).class_name('Ai::A2aTaskEvent').dependent(:destroy) }
  end

  describe 'validations' do
    subject { build(:ai_a2a_task) }

    it { should validate_presence_of(:task_id) }
    it { should validate_uniqueness_of(:task_id) }
    it { should validate_inclusion_of(:status).in_array(%w[pending active completed failed cancelled input_required]) }
  end

  describe 'state machine' do
    let(:task) { create(:ai_a2a_task) }

    describe '#start!' do
      it 'transitions from pending to active' do
        expect { task.start! }.to change { task.status }.from('pending').to('active')
      end

      it 'sets started_at timestamp' do
        task.start!
        expect(task.started_at).to be_present
      end

      it 'creates a status_change event' do
        expect { task.start! }.to change { task.events.count }.by(1)
      end
    end

    describe '#complete!' do
      let(:task) { create(:ai_a2a_task, :active) }
      let(:output) { { 'result' => 'success' } }

      it 'transitions from active to completed' do
        expect { task.complete!(output) }.to change { task.status }.from('active').to('completed')
      end

      it 'sets output and completed_at' do
        task.complete!(output)
        expect(task.output).to eq(output)
        expect(task.completed_at).to be_present
      end
    end

    describe '#fail!' do
      let(:task) { create(:ai_a2a_task, :active) }

      it 'transitions from active to failed' do
        expect { task.fail!('Error occurred') }.to change { task.status }.from('active').to('failed')
      end

      it 'sets error_message' do
        task.fail!('Something went wrong')
        expect(task.error_message).to eq('Something went wrong')
      end
    end

    describe '#cancel!' do
      let(:task) { create(:ai_a2a_task, :active) }

      it 'transitions to cancelled' do
        expect { task.cancel!('User requested') }.to change { task.status }.to('cancelled')
      end
    end

    describe '#request_input!' do
      let(:task) { create(:ai_a2a_task, :active) }

      it 'transitions to input_required' do
        expect { task.request_input! }.to change { task.status }.to('input_required')
      end
    end

    describe '#provide_input!' do
      let(:task) { create(:ai_a2a_task, :input_required) }
      let(:input) { { 'additional_data' => 'value' } }

      it 'transitions back to active' do
        expect { task.provide_input!(input) }.to change { task.status }.from('input_required').to('active')
      end

      it 'merges input into existing input' do
        original_input = task.input.dup
        task.provide_input!(input)
        expect(task.input).to include(original_input)
      end
    end
  end

  describe 'scopes' do
    let!(:pending_task) { create(:ai_a2a_task) }
    let!(:active_task) { create(:ai_a2a_task, :active) }
    let!(:completed_task) { create(:ai_a2a_task, :completed) }
    let!(:failed_task) { create(:ai_a2a_task, :failed) }

    describe '.pending' do
      it 'returns only pending tasks' do
        expect(Ai::A2aTask.pending).to contain_exactly(pending_task)
      end
    end

    describe '.active' do
      it 'returns only active tasks' do
        expect(Ai::A2aTask.active).to contain_exactly(active_task)
      end
    end

    describe '.completed' do
      it 'returns only completed tasks' do
        expect(Ai::A2aTask.completed).to contain_exactly(completed_task)
      end
    end

    describe '.terminal' do
      it 'returns completed, failed, and cancelled tasks' do
        expect(Ai::A2aTask.terminal).to include(completed_task, failed_task)
      end
    end
  end

  describe '#duration_ms' do
    let(:task) { create(:ai_a2a_task, :completed) }

    it 'calculates duration in milliseconds' do
      expect(task.duration_ms).to be_a(Integer)
      expect(task.duration_ms).to be > 0
    end
  end

  describe '#add_artifact!' do
    let(:task) { create(:ai_a2a_task, :active) }
    let(:artifact_data) do
      {
        name: 'result.json',
        mime_type: 'application/json',
        data: { 'key' => 'value' }
      }
    end

    it 'adds artifact to artifacts array' do
      task.add_artifact!(artifact_data)
      expect(task.artifacts.length).to eq(1)
      expect(task.artifacts.first['name']).to eq('result.json')
    end

    it 'generates artifact_id' do
      task.add_artifact!(artifact_data)
      expect(task.artifacts.first['artifact_id']).to be_present
    end

    it 'creates artifact_added event' do
      expect { task.add_artifact!(artifact_data) }.to change { task.events.count }.by(1)
    end
  end

  describe '#to_a2a_json' do
    let(:task) { create(:ai_a2a_task, :completed, :with_artifacts) }

    it 'returns A2A-compliant task JSON' do
      json = task.to_a2a_json

      expect(json).to include(
        'id' => task.task_id,
        'status' => task.status
      )
    end

    it 'includes artifacts when present' do
      json = task.to_a2a_json
      expect(json['artifacts']).to be_an(Array)
    end
  end
end
