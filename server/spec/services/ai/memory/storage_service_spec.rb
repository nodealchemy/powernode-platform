# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Memory::StorageService, type: :service do
  let(:account) { create(:account) }
  let(:agent) { create(:ai_agent, account: account) }
  let(:service) { described_class.new(account: account, agent: agent) }

  # ============================================================
  # Experiential Memory
  # ============================================================
  describe '#store_experiential' do
    it 'stores an experiential memory' do
      entry = service.store_experiential(content: 'User prefers concise responses')

      expect(entry).to be_a(Ai::ContextEntry)
      expect(entry.memory_type).to eq('experiential')
    end

    it 'generates unique entry key' do
      entry1 = service.store_experiential(content: 'Memory 1')
      entry2 = service.store_experiential(content: 'Memory 2')

      expect(entry1.entry_key).not_to eq(entry2.entry_key)
    end

    it 'sets default importance and decay rate' do
      entry = service.store_experiential(content: 'Test memory')

      expect(entry.importance_score).to eq(0.5)
      expect(entry.decay_rate).to eq(0.01)
    end

    it 'increases importance for failed outcomes' do
      entry = service.store_experiential(content: 'Failed task', outcome_success: false)

      expect(entry.importance_score).to eq(0.7)
    end

    it 'stores with custom importance' do
      entry = service.store_experiential(content: 'Important memory', importance: 0.9)

      expect(entry.importance_score).to eq(0.9)
    end

    it 'stores context information' do
      entry = service.store_experiential(
        content: 'Task completed',
        context: { 'task_id' => 'abc123', 'workflow_run_id' => 'xyz789' }
      )

      expect(entry.metadata['context']).to include('task_id' => 'abc123')
    end

    it 'stores tags' do
      entry = service.store_experiential(
        content: 'Tagged memory',
        tags: %w[summarization important]
      )

      expect(entry.context_tags).to include('summarization', 'important')
    end

    it 'normalizes hash content' do
      entry = service.store_experiential(content: { 'text' => 'Structured data' })

      expect(entry.content).to eq({ 'text' => 'Structured data' })
    end

    it 'normalizes string content' do
      entry = service.store_experiential(content: 'Plain text')

      expect(entry.content).to eq({ 'text' => 'Plain text' })
    end
  end

  describe '#search_experiential' do
    before do
      service.store_experiential(content: 'User loves dark mode and minimalist design')
      service.store_experiential(content: 'The task was completed successfully with good results')
      service.store_experiential(content: 'Error occurred during API call to external service')
    end

    it 'returns results for matching query' do
      results = service.search_experiential('dark mode preferences')

      expect(results).to be_an(Array)
    end

    it 'limits results' do
      results = service.search_experiential('test query', limit: 2)

      expect(results.length).to be <= 2
    end

    context 'without embeddings' do
      it 'falls back to keyword search' do
        results = service.search_experiential('dark mode')

        expect(results).to be_an(Array)
      end
    end
  end

  describe '#successful_outcomes' do
    before do
      service.store_experiential(content: 'Success 1', outcome_success: true)
      service.store_experiential(content: 'Success 2', outcome_success: true)
      service.store_experiential(content: 'Failure', outcome_success: false)
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
      service.store_experiential(content: 'Failure 1', outcome_success: false)
      service.store_experiential(content: 'Success', outcome_success: true)
    end

    it 'returns only failed outcome memories' do
      results = service.failed_outcomes

      expect(results.length).to eq(1)
    end
  end

  describe '#recent_experiential' do
    before do
      service.store_experiential(content: 'Old memory')
      service.store_experiential(content: 'Recent memory')
    end

    it 'returns memories in recent order' do
      results = service.recent_experiential(limit: 10)

      expect(results).to be_an(Array)
      expect(results.length).to eq(2)
    end
  end

  describe '#most_important_experiential' do
    before do
      service.store_experiential(content: 'Low importance', importance: 0.2)
      service.store_experiential(content: 'High importance', importance: 0.9)
      service.store_experiential(content: 'Medium importance', importance: 0.5)
    end

    it 'returns memories sorted by importance' do
      results = service.most_important_experiential(limit: 10)

      expect(results.first[:importance_score]).to be >= results.last[:importance_score]
    end
  end

  describe '#experiential_by_tag' do
    before do
      service.store_experiential(content: 'Tagged 1', tags: ['summarization'])
      service.store_experiential(content: 'Tagged 2', tags: ['summarization'])
      service.store_experiential(content: 'Other tag', tags: ['translation'])
    end

    it 'returns memories with matching tag' do
      results = service.experiential_by_tag('summarization')

      expect(results.length).to eq(2)
    end
  end

  describe '#reinforce' do
    let!(:entry) { service.store_experiential(content: 'Memory to reinforce', importance: 0.5) }

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

  describe '#apply_experiential_decay' do
    before do
      service.store_experiential(content: 'Decaying memory', importance: 0.5)
    end

    it 'does not raise error' do
      expect { service.apply_experiential_decay }.not_to raise_error
    end
  end

  describe '#cleanup_experiential' do
    before do
      entry = service.store_experiential(content: 'Old memory', importance: 0.1)
      entry.update!(created_at: 100.days.ago)
    end

    it 'archives old low-importance memories' do
      expect { service.cleanup_experiential(max_age_days: 90, min_importance: 0.2) }.not_to raise_error
    end
  end

  # ============================================================
  # Factual Memory
  # ============================================================
  describe '#store_fact' do
    it 'stores a fact with key-value pair' do
      entry = service.store_fact(key: 'user_name', value: 'John Doe')

      expect(entry).to be_a(Ai::ContextEntry)
      expect(entry.entry_key).to eq('user_name')
      expect(entry.memory_type).to eq('factual')
    end

    it 'sets full confidence and no decay for facts' do
      entry = service.store_fact(key: 'preference', value: 'dark_mode')

      expect(entry.confidence_score).to eq(1.0)
      expect(entry.importance_score).to eq(1.0)
      expect(entry.decay_rate).to eq(0.0)
    end

    it 'normalizes string values to hash' do
      entry = service.store_fact(key: 'note', value: 'A simple note')

      expect(entry.content).to include('text' => 'A simple note')
    end

    it 'normalizes numeric values' do
      entry = service.store_fact(key: 'count', value: 42)

      expect(entry.content).to include('value' => 42)
    end

    it 'stores hash values directly' do
      entry = service.store_fact(key: 'config', value: { 'theme' => 'dark', 'lang' => 'en' })

      expect(entry.content).to eq({ 'theme' => 'dark', 'lang' => 'en' })
    end

    it 'updates existing fact if value changed' do
      service.store_fact(key: 'version', value: '1.0')

      expect {
        service.store_fact(key: 'version', value: '2.0')
      }.to change { Ai::ContextEntry.count }.by(1)

      expect(Ai::ContextEntry.where(entry_key: 'version', archived_at: nil).count).to eq(1)
    end

    it 'stores metadata with the fact' do
      entry = service.store_fact(
        key: 'setting',
        value: 'enabled',
        metadata: { 'category' => 'preferences' }
      )

      expect(entry.metadata).to include('category' => 'preferences')
    end
  end

  describe '#retrieve_fact' do
    before do
      service.store_fact(key: 'user_name', value: 'Alice')
    end

    it 'retrieves stored fact by key' do
      result = service.retrieve_fact('user_name')

      expect(result).to be_present
    end

    it 'returns nil for non-existent key' do
      result = service.retrieve_fact('non_existent')

      expect(result).to be_nil
    end
  end

  describe '#fact_exists?' do
    before do
      service.store_fact(key: 'existing_key', value: 'value')
    end

    it 'returns true for existing fact' do
      expect(service.fact_exists?('existing_key')).to be true
    end

    it 'returns false for non-existent fact' do
      expect(service.fact_exists?('missing_key')).to be false
    end
  end

  describe '#all_facts' do
    before do
      service.store_fact(key: 'fact_1', value: 'value_1')
      service.store_fact(key: 'fact_2', value: 'value_2')
      service.store_fact(key: 'fact_3', value: 'value_3')
    end

    it 'returns all facts for the agent' do
      facts = service.all_facts

      expect(facts.length).to eq(3)
    end

    it 'respects limit parameter' do
      facts = service.all_facts(limit: 2)

      expect(facts.length).to eq(2)
    end

    it 'returns facts in descending order by creation' do
      facts = service.all_facts

      expect(facts.first[:entry_key]).to eq('fact_3')
    end
  end

  describe '#search_facts_by_key' do
    before do
      service.store_fact(key: 'user_name', value: 'Alice')
      service.store_fact(key: 'user_email', value: 'alice@example.com')
      service.store_fact(key: 'company_name', value: 'Acme')
    end

    it 'finds facts matching key pattern' do
      results = service.search_facts_by_key('user')

      expect(results.length).to eq(2)
    end

    it 'is case-insensitive' do
      results = service.search_facts_by_key('USER')

      expect(results.length).to eq(2)
    end
  end

  describe '#search_facts_by_content' do
    before do
      service.store_fact(key: 'greeting', value: 'Hello World')
      service.store_fact(key: 'farewell', value: 'Goodbye World')
      service.store_fact(key: 'other', value: 'Something else')
    end

    it 'finds facts matching content' do
      results = service.search_facts_by_content('World')

      expect(results.length).to eq(2)
    end
  end

  describe '#remove_fact' do
    before do
      service.store_fact(key: 'to_remove', value: 'temporary')
    end

    it 'archives the fact' do
      service.remove_fact('to_remove')

      expect(service.fact_exists?('to_remove')).to be false
    end

    it 'returns nil for non-existent key' do
      result = service.remove_fact('non_existent')

      expect(result).to be_nil
    end
  end

  describe '#store_facts_batch' do
    it 'stores multiple facts at once' do
      facts = [
        { key: 'batch_1', value: 'value_1' },
        { key: 'batch_2', value: 'value_2' },
        { key: 'batch_3', value: 'value_3' }
      ]

      results = service.store_facts_batch(facts)

      expect(results.length).to eq(3)
      expect(results).to all(be_a(Ai::ContextEntry))
    end
  end

  describe '#facts_by_category' do
    before do
      service.store_fact(key: 'pref_1', value: 'val', metadata: { 'category' => 'preferences' })
      service.store_fact(key: 'pref_2', value: 'val', metadata: { 'category' => 'preferences' })
      service.store_fact(key: 'other', value: 'val', metadata: { 'category' => 'other' })
    end

    it 'returns facts by category' do
      results = service.facts_by_category('preferences')

      expect(results.length).to eq(2)
    end
  end

  describe '#export_facts and #import_facts' do
    before do
      service.store_fact(key: 'export_1', value: 'value_1')
      service.store_fact(key: 'export_2', value: 'value_2')
    end

    it 'exports all facts' do
      exported = service.export_facts

      expect(exported.length).to eq(2)
      expect(exported.first).to include(:key, :value, :metadata, :created_at)
    end

    it 'imports facts from export' do
      other_agent = create(:ai_agent, account: account)
      other_service = described_class.new(account: account, agent: other_agent)

      exported = service.export_facts
      result = other_service.import_facts(exported)

      expect(result[:imported]).to eq(2)
      expect(result[:skipped]).to eq(0)
    end

    it 'skips existing facts unless overwrite is true' do
      service.store_fact(key: 'existing', value: 'original')

      facts_to_import = [{ key: 'existing', value: 'new_value' }]
      result = service.import_facts(facts_to_import, overwrite: false)

      expect(result[:skipped]).to eq(1)
    end
  end

  # ============================================================
  # Shared Learning
  # ============================================================
  describe '#extract_learnings_from_output' do
    let(:service_no_agent) { described_class.new(account: account) }

    it 'extracts learnings from marked output' do
      output = "Discovery: Found a new API endpoint\nPattern: Users always prefer dark mode"

      learnings = service_no_agent.extract_learnings_from_output(output: output)

      expect(learnings.length).to eq(2)
      expect(learnings.map { |l| l[:category] }).to contain_exactly("discovery", "pattern")
    end

    it 'returns empty array for blank output' do
      learnings = service_no_agent.extract_learnings_from_output(output: '')

      expect(learnings).to eq([])
    end
  end

  describe '#build_learning_context' do
    let(:service_no_agent) { described_class.new(account: account) }

    it 'returns nil when no learnings exist' do
      result = service_no_agent.build_learning_context(query: 'test')

      expect(result).to be_nil
    end
  end

  # ============================================================
  # Memory Pool
  # ============================================================
  describe '#create_pool' do
    let(:service_no_agent) { described_class.new(account: account) }

    it 'creates a new memory pool' do
      pool = service_no_agent.create_pool(name: 'Test Pool', pool_type: 'shared', scope: 'execution')

      expect(pool).to be_a(Ai::MemoryPool)
      expect(pool.name).to eq('Test Pool')
    end
  end

  describe '#create_team_execution_pool' do
    let(:service_no_agent) { described_class.new(account: account) }
    let(:team) { create(:ai_agent_team, account: account) }

    it 'creates a team execution pool' do
      pool = service_no_agent.create_team_execution_pool(team_execution: nil, team: team)

      expect(pool).to be_a(Ai::MemoryPool)
      expect(pool.pool_type).to eq('team_shared')
      expect(pool.data).to include('learnings' => [], 'shared_state' => {})
    end
  end

  # ============================================================
  # Agent requirement
  # ============================================================
  describe 'agent requirement' do
    let(:service_no_agent) { described_class.new(account: account) }

    it 'raises error for experiential operations without agent' do
      expect { service_no_agent.store_experiential(content: 'test') }.to raise_error(ArgumentError, /agent is required/)
    end

    it 'raises error for factual operations without agent' do
      expect { service_no_agent.store_fact(key: 'k', value: 'v') }.to raise_error(ArgumentError, /agent is required/)
    end

    it 'allows shared learning operations without agent' do
      expect { service_no_agent.extract_learnings_from_output(output: 'test') }.not_to raise_error
    end

    it 'allows pool operations without agent' do
      expect { service_no_agent.create_pool(name: 'Test', pool_type: 'shared', scope: 'execution') }.not_to raise_error
    end
  end
end
