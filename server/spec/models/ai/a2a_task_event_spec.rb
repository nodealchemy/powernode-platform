# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::A2aTaskEvent, type: :model do
  describe 'associations' do
    it { should belong_to(:a2a_task).class_name('Ai::A2aTask') }
  end

  describe 'validations' do
    subject { build(:ai_a2a_task_event) }

    it { should validate_presence_of(:event_type) }
    it { should validate_inclusion_of(:event_type).in_array(%w[status_change artifact_added message progress error]) }
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

  describe '#to_sse_format' do
    let(:event) { create(:ai_a2a_task_event, :progress) }

    it 'returns SSE-formatted string' do
      sse = event.to_sse_format

      expect(sse).to include("event: #{event.event_type}")
      expect(sse).to include("id: #{event.id}")
      expect(sse).to include("data:")
    end

    it 'includes JSON data' do
      sse = event.to_sse_format
      data_line = sse.lines.find { |l| l.start_with?('data:') }
      json_data = JSON.parse(data_line.sub('data: ', '').strip)

      expect(json_data).to include('current', 'total')
    end
  end

  describe '#broadcast!' do
    let(:event) { create(:ai_a2a_task_event) }

    it 'broadcasts to ActionCable channel' do
      expect(ActionCable.server).to receive(:broadcast).with(
        "a2a_task_#{event.a2a_task.task_id}",
        hash_including('event_type' => event.event_type)
      )

      event.broadcast!
    end
  end
end
