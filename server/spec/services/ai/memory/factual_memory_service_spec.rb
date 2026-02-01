# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Memory::FactualMemoryService, type: :service do
  let(:account) { create(:account) }
  let(:agent) { create(:ai_agent, account: account) }
  let(:service) { described_class.new(agent: agent, account: account) }

  describe '#store' do
    it 'stores a fact with key-value pair' do
      entry = service.store(key: 'user_name', value: 'John Doe')

      expect(entry).to be_a(Ai::ContextEntry)
      expect(entry.entry_key).to eq('user_name')
      expect(entry.memory_type).to eq('factual')
    end

    it 'sets full confidence and no decay for facts' do
      entry = service.store(key: 'preference', value: 'dark_mode')

      expect(entry.confidence_score).to eq(1.0)
      expect(entry.importance_score).to eq(1.0)
      expect(entry.decay_rate).to eq(0.0)
    end

    it 'normalizes string values to hash' do
      entry = service.store(key: 'note', value: 'A simple note')

      expect(entry.content).to include('text' => 'A simple note')
    end

    it 'normalizes numeric values' do
      entry = service.store(key: 'count', value: 42)

      expect(entry.content).to include('value' => 42)
    end

    it 'stores hash values directly' do
      entry = service.store(key: 'config', value: { 'theme' => 'dark', 'lang' => 'en' })

      expect(entry.content).to eq({ 'theme' => 'dark', 'lang' => 'en' })
    end

    it 'updates existing fact if value changed' do
      service.store(key: 'version', value: '1.0')

      # Versioning creates a new entry and archives the old one
      expect {
        service.store(key: 'version', value: '2.0')
      }.to change { Ai::ContextEntry.count }.by(1)

      # Only one active entry should exist
      expect(Ai::ContextEntry.where(entry_key: 'version', archived_at: nil).count).to eq(1)
    end

    it 'stores metadata with the fact' do
      entry = service.store(
        key: 'setting',
        value: 'enabled',
        metadata: { 'category' => 'preferences' }
      )

      expect(entry.metadata).to include('category' => 'preferences')
    end
  end

  describe '#retrieve' do
    before do
      service.store(key: 'user_name', value: 'Alice')
    end

    it 'retrieves stored fact by key' do
      result = service.retrieve('user_name')

      expect(result).to be_present
    end

    it 'returns nil for non-existent key' do
      result = service.retrieve('non_existent')

      expect(result).to be_nil
    end
  end

  describe '#exists?' do
    before do
      service.store(key: 'existing_key', value: 'value')
    end

    it 'returns true for existing fact' do
      expect(service.exists?('existing_key')).to be true
    end

    it 'returns false for non-existent fact' do
      expect(service.exists?('missing_key')).to be false
    end
  end

  describe '#all' do
    before do
      service.store(key: 'fact_1', value: 'value_1')
      service.store(key: 'fact_2', value: 'value_2')
      service.store(key: 'fact_3', value: 'value_3')
    end

    it 'returns all facts for the agent' do
      facts = service.all

      expect(facts.length).to eq(3)
    end

    it 'respects limit parameter' do
      facts = service.all(limit: 2)

      expect(facts.length).to eq(2)
    end

    it 'returns facts in descending order by creation' do
      facts = service.all

      expect(facts.first[:entry_key]).to eq('fact_3')
    end
  end

  describe '#search_by_key' do
    before do
      service.store(key: 'user_name', value: 'Alice')
      service.store(key: 'user_email', value: 'alice@example.com')
      service.store(key: 'company_name', value: 'Acme')
    end

    it 'finds facts matching key pattern' do
      results = service.search_by_key('user')

      expect(results.length).to eq(2)
    end

    it 'is case-insensitive' do
      results = service.search_by_key('USER')

      expect(results.length).to eq(2)
    end
  end

  describe '#search_by_content' do
    before do
      service.store(key: 'greeting', value: 'Hello World')
      service.store(key: 'farewell', value: 'Goodbye World')
      service.store(key: 'other', value: 'Something else')
    end

    it 'finds facts matching content' do
      results = service.search_by_content('World')

      expect(results.length).to eq(2)
    end
  end

  describe '#remove' do
    before do
      service.store(key: 'to_remove', value: 'temporary')
    end

    it 'archives the fact' do
      service.remove('to_remove')

      expect(service.exists?('to_remove')).to be false
    end

    it 'returns nil for non-existent key' do
      result = service.remove('non_existent')

      expect(result).to be_nil
    end
  end

  describe '#store_batch' do
    it 'stores multiple facts at once' do
      facts = [
        { key: 'batch_1', value: 'value_1' },
        { key: 'batch_2', value: 'value_2' },
        { key: 'batch_3', value: 'value_3' }
      ]

      results = service.store_batch(facts)

      expect(results.length).to eq(3)
      expect(results).to all(be_a(Ai::ContextEntry))
    end
  end

  describe '#by_category' do
    before do
      service.store(key: 'pref_1', value: 'val', metadata: { 'category' => 'preferences' })
      service.store(key: 'pref_2', value: 'val', metadata: { 'category' => 'preferences' })
      service.store(key: 'other', value: 'val', metadata: { 'category' => 'other' })
    end

    it 'returns facts by category' do
      results = service.by_category('preferences')

      expect(results.length).to eq(2)
    end
  end

  describe '#export and #import' do
    before do
      service.store(key: 'export_1', value: 'value_1')
      service.store(key: 'export_2', value: 'value_2')
    end

    it 'exports all facts' do
      exported = service.export

      expect(exported.length).to eq(2)
      expect(exported.first).to include(:key, :value, :metadata, :created_at)
    end

    it 'imports facts from export' do
      other_agent = create(:ai_agent, account: account)
      other_service = described_class.new(agent: other_agent, account: account)

      exported = service.export
      result = other_service.import(exported)

      expect(result[:imported]).to eq(2)
      expect(result[:skipped]).to eq(0)
    end

    it 'skips existing facts unless overwrite is true' do
      service.store(key: 'existing', value: 'original')

      facts_to_import = [{ key: 'existing', value: 'new_value' }]
      result = service.import(facts_to_import, overwrite: false)

      expect(result[:skipped]).to eq(1)
    end
  end
end
