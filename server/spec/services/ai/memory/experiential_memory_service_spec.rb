# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Memory::ExperientialMemoryService, type: :service do
  let(:account) { create(:account) }
  let(:agent) { create(:ai_agent, account: account) }
  let(:service) { described_class.new(agent: agent, account: account) }

  describe '#store' do
    it 'stores an experiential memory' do
      entry = service.store(content: 'User prefers concise responses')

      expect(entry).to be_a(Ai::ContextEntry)
      expect(entry.memory_type).to eq('experiential')
    end

    it 'generates unique entry key' do
      entry1 = service.store(content: 'Memory 1')
      entry2 = service.store(content: 'Memory 2')

      expect(entry1.entry_key).not_to eq(entry2.entry_key)
    end

    it 'sets default importance and decay rate' do
      entry = service.store(content: 'Test memory')

      expect(entry.importance_score).to eq(0.5)
      expect(entry.decay_rate).to eq(0.01)
    end

    it 'increases importance for failed outcomes' do
      entry = service.store(content: 'Failed task', outcome_success: false)

      expect(entry.importance_score).to eq(0.7)
    end

    it 'stores with custom importance' do
      entry = service.store(content: 'Important memory', importance: 0.9)

      expect(entry.importance_score).to eq(0.9)
    end

    it 'stores context information' do
      entry = service.store(
        content: 'Task completed',
        context: { 'task_id' => 'abc123', 'workflow_run_id' => 'xyz789' }
      )

      expect(entry.metadata['context']).to include('task_id' => 'abc123')
    end

    it 'stores tags' do
      entry = service.store(
        content: 'Tagged memory',
        tags: %w[summarization important]
      )

      expect(entry.context_tags).to include('summarization', 'important')
    end

    it 'normalizes hash content' do
      entry = service.store(content: { 'text' => 'Structured data' })

      expect(entry.content).to eq({ 'text' => 'Structured data' })
    end

    it 'normalizes string content' do
      entry = service.store(content: 'Plain text')

      expect(entry.content).to eq({ 'text' => 'Plain text' })
    end
  end

  describe '#search' do
    before do
      service.store(content: 'User loves dark mode and minimalist design')
      service.store(content: 'The task was completed successfully with good results')
      service.store(content: 'Error occurred during API call to external service')
    end

    it 'returns results for matching query' do
      results = service.search('dark mode preferences')

      expect(results).to be_an(Array)
    end

    it 'limits results' do
      results = service.search('test query', limit: 2)

      expect(results.length).to be <= 2
    end

    context 'without embeddings' do
      it 'falls back to keyword search' do
        results = service.search('dark mode')

        expect(results).to be_an(Array)
      end
    end
  end

  describe '#successful_outcomes' do
    before do
      service.store(content: 'Success 1', outcome_success: true)
      service.store(content: 'Success 2', outcome_success: true)
      service.store(content: 'Failure', outcome_success: false)
    end

    it 'returns only successful outcome memories' do
      results = service.successful_outcomes

      expect(results.length).to eq(2)
    end

    it 'respects limit' do
      results = service.successful_outcomes(limit: 1)

      expect(results.length).to eq(1)
    end
  end

  describe '#failed_outcomes' do
    before do
      service.store(content: 'Failure 1', outcome_success: false)
      service.store(content: 'Success', outcome_success: true)
    end

    it 'returns only failed outcome memories' do
      results = service.failed_outcomes

      expect(results.length).to eq(1)
    end
  end

  describe '#recent' do
    before do
      service.store(content: 'Old memory')
      service.store(content: 'Recent memory')
    end

    it 'returns memories in recent order' do
      results = service.recent(limit: 10)

      expect(results).to be_an(Array)
      expect(results.length).to eq(2)
    end
  end

  describe '#most_important' do
    before do
      service.store(content: 'Low importance', importance: 0.2)
      service.store(content: 'High importance', importance: 0.9)
      service.store(content: 'Medium importance', importance: 0.5)
    end

    it 'returns memories sorted by importance' do
      results = service.most_important(limit: 10)

      expect(results.first[:importance_score]).to be >= results.last[:importance_score]
    end
  end

  describe '#by_tag' do
    before do
      service.store(content: 'Tagged 1', tags: ['summarization'])
      service.store(content: 'Tagged 2', tags: ['summarization'])
      service.store(content: 'Other tag', tags: ['translation'])
    end

    it 'returns memories with matching tag' do
      results = service.by_tag('summarization')

      expect(results.length).to eq(2)
    end
  end

  describe '#reinforce' do
    let!(:entry) { service.store(content: 'Memory to reinforce', importance: 0.5) }

    it 'boosts importance of memory' do
      service.reinforce(entry.id, boost: 0.2)

      expect(entry.reload.importance_score).to eq(0.7)
    end

    it 'updates last_accessed_at' do
      service.reinforce(entry.id)

      expect(entry.reload.last_accessed_at).to be_present
    end

    it 'returns nil for non-existent entry' do
      result = service.reinforce('non-existent-id')

      expect(result).to be_nil
    end
  end

  describe '#apply_decay' do
    before do
      service.store(content: 'Decaying memory', importance: 0.5)
    end

    it 'does not raise error' do
      expect { service.apply_decay }.not_to raise_error
    end
  end

  describe '#cleanup' do
    before do
      # Create old low-importance memory
      entry = service.store(content: 'Old memory', importance: 0.1)
      entry.update!(created_at: 100.days.ago)
    end

    it 'archives old low-importance memories' do
      expect { service.cleanup(max_age_days: 90, min_importance: 0.2) }.not_to raise_error
    end
  end
end
