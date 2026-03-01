# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::A2aTaskEvent, type: :model do
  describe 'associations' do
    it { should belong_to(:a2a_task).class_name('Ai::A2aTask') }
  end

  describe 'validations' do
    subject { build(:ai_a2a_task_event) }

    it { should validate_presence_of(:event_type) }
    it { should validate_inclusion_of(:event_type).in_array(%w[status_change artifact_added message progress error cancelled]) }
  end

  describe 'scopes' do
    let(:task) { create(:ai_a2a_task) }
    let!(:status_event) { create(:ai_a2a_task_event, :status_change, a2a_task: task) }
    let!(:artifact_event) { create(:ai_a2a_task_event, :artifact_added, a2a_task: task) }
    let!(:progress_event) { create(:ai_a2a_task_event, :progress, a2a_task: task) }

    describe '.status_changes' do
      it 'returns only status_change events' do
        expect(Ai::A2aTaskEvent.status_changes).to contain_exactly(status_event)
      end
    end

    describe '.artifacts' do
      it 'returns only artifact_added events' do
        expect(Ai::A2aTaskEvent.artifacts).to contain_exactly(artifact_event)
      end
    end

    describe '.since' do
      it 'returns events since given timestamp' do
        old_event = create(:ai_a2a_task_event, a2a_task: task, created_at: 1.hour.ago)
        recent_event = create(:ai_a2a_task_event, a2a_task: task, created_at: 1.minute.ago)

        events = Ai::A2aTaskEvent.since(30.minutes.ago)
        expect(events).to include(recent_event)
        expect(events).not_to include(old_event)
      end
    end
  end

  describe '#to_sse_json' do
    let(:event) { create(:ai_a2a_task_event, :progress) }

    it 'returns SSE-formatted hash' do
      sse = event.to_sse_json

      expect(sse[:id]).to eq(event.event_id)
      expect(sse[:type]).to eq('task.progress')
      expect(sse[:data]).to be_present
    end

    it 'includes JSON data' do
      sse = event.to_sse_json
      json_data = JSON.parse(sse[:data])

      expect(json_data).to include('taskId')
    end
  end

  describe 'auto-broadcast on create' do
    let(:task) { create(:ai_a2a_task) }

    it 'broadcasts to ActionCable channel on create' do
      expect(ActionCable.server).to receive(:broadcast).with(
        "a2a_task_#{task.task_id}",
        hash_including(:id, :type, :data)
      )

      # Also expect broadcast to account channel
      allow(McpChannel).to receive(:broadcast_to)

      create(:ai_a2a_task_event, a2a_task: task)
    end
  end
end
