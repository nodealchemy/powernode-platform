# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Memory::WorkingMemoryService, type: :service do
  let(:account) { create(:account) }
  let(:agent) { create(:ai_agent, account: account) }
  let(:service) { described_class.new(agent: agent, account: account) }

  before do
    # Clear any existing working memory
    service.clear
  end

  describe '#store and #retrieve' do
    it 'stores and retrieves a string value' do
      service.store('key', 'value')

      expect(service.retrieve('key')).to eq('value')
    end

    it 'stores and retrieves numeric values' do
      service.store('count', 42)

      expect(service.retrieve('count')).to eq(42)
    end

    it 'stores and retrieves hash values' do
      data = { 'name' => 'test', 'items' => [1, 2, 3] }
      service.store('data', data)

      expect(service.retrieve('data')).to eq(data)
    end

    it 'stores and retrieves array values' do
      items = %w[one two three]
      service.store('items', items)

      expect(service.retrieve('items')).to eq(items)
    end

    it 'stores and retrieves boolean values' do
      service.store('flag', true)

      expect(service.retrieve('flag')).to be true
    end

    it 'returns nil for non-existent key' do
      expect(service.retrieve('non_existent')).to be_nil
    end
  end

  describe '#exists?' do
    it 'returns true for existing key' do
      service.store('existing', 'value')

      expect(service.exists?('existing')).to be true
    end

    it 'returns false for non-existent key' do
      expect(service.exists?('missing')).to be false
    end
  end

  describe '#remove' do
    before do
      service.store('to_remove', 'value')
    end

    it 'removes the key' do
      service.remove('to_remove')

      expect(service.exists?('to_remove')).to be false
    end
  end

  describe '#keys' do
    before do
      service.store('key1', 'value1')
      service.store('key2', 'value2')
    end

    it 'returns all keys' do
      keys = service.keys

      expect(keys).to include('key1', 'key2')
    end
  end

  describe '#all' do
    before do
      service.store('key1', 'value1')
      service.store('key2', 'value2')
    end

    it 'returns all key-value pairs' do
      all = service.all

      expect(all).to include('key1' => 'value1', 'key2' => 'value2')
    end
  end

  describe '#clear' do
    before do
      service.store('key1', 'value1')
      service.store('key2', 'value2')
    end

    it 'removes all working memory' do
      service.clear

      expect(service.all).to be_empty
    end
  end

  describe '#store_task_state and #retrieve_task_state' do
    it 'stores and retrieves task state' do
      state = { 'step' => 2, 'status' => 'processing' }
      service.store_task_state(state)

      expect(service.retrieve_task_state).to eq(state)
    end
  end

  describe '#store_intermediate_result and #retrieve_intermediate_result' do
    it 'stores and retrieves intermediate results' do
      service.store_intermediate_result('step1', { 'data' => 'result1' })
      service.store_intermediate_result('step2', { 'data' => 'result2' })

      expect(service.retrieve_intermediate_result('step1')).to eq({ 'data' => 'result1' })
      expect(service.retrieve_intermediate_result('step2')).to eq({ 'data' => 'result2' })
    end
  end

  describe '#all_intermediate_results' do
    before do
      service.store_intermediate_result('step1', 'result1')
      service.store_intermediate_result('step2', 'result2')
      service.store('regular_key', 'regular_value')
    end

    it 'returns only intermediate results' do
      results = service.all_intermediate_results

      expect(results).to include('step1' => 'result1', 'step2' => 'result2')
      expect(results).not_to have_key('regular_key')
    end
  end

  describe '#store_conversation_context and #retrieve_conversation_context' do
    it 'stores and retrieves conversation context' do
      messages = [
        { 'role' => 'user', 'content' => 'Hello' },
        { 'role' => 'assistant', 'content' => 'Hi there!' }
      ]
      service.store_conversation_context(messages)

      expect(service.retrieve_conversation_context).to eq(messages)
    end

    it 'returns empty array when no context exists' do
      expect(service.retrieve_conversation_context).to eq([])
    end
  end

  describe '#append_to_conversation' do
    it 'appends messages to conversation context' do
      service.append_to_conversation(role: 'user', content: 'First message')
      service.append_to_conversation(role: 'assistant', content: 'Reply')

      context = service.retrieve_conversation_context
      expect(context.length).to eq(2)
      expect(context.first['content']).to eq('First message')
    end
  end

  describe '#store_tool_state and #retrieve_tool_state' do
    it 'stores and retrieves tool state' do
      state = { 'status' => 'running', 'progress' => 50 }
      service.store_tool_state('search_tool', state)

      expect(service.retrieve_tool_state('search_tool')).to eq(state)
    end
  end

  describe '#store_scratch_pad and #retrieve_scratch_pad' do
    it 'stores and retrieves scratch pad content' do
      service.store_scratch_pad('Initial thoughts')

      expect(service.retrieve_scratch_pad).to eq('Initial thoughts')
    end
  end

  describe '#append_to_scratch_pad' do
    it 'appends to existing scratch pad' do
      service.store_scratch_pad('First note')
      service.append_to_scratch_pad('Second note')

      content = service.retrieve_scratch_pad
      expect(content).to include('First note')
      expect(content).to include('Second note')
    end
  end

  describe '#statistics' do
    before do
      service.store('key1', 'value1')
      service.store('key2', { 'nested' => 'data' })
    end

    it 'returns statistics about working memory' do
      stats = service.statistics

      expect(stats).to include(:key_count, :total_size_bytes, :agent_id)
      expect(stats[:key_count]).to eq(2)
    end
  end

  describe 'with task context' do
    let(:task) { create(:ai_a2a_task, account: account) }
    let(:task_service) { described_class.new(agent: agent, account: account, task: task) }

    before { task_service.clear }

    it 'isolates memory by task' do
      task_service.store('task_key', 'task_value')
      service.store('agent_key', 'agent_value')

      expect(task_service.retrieve('task_key')).to eq('task_value')
      expect(task_service.retrieve('agent_key')).to be_nil
    end
  end

  describe 'with workflow context' do
    let(:workflow_run) { create(:ai_workflow_run, account: account) }
    let(:workflow_service) do
      described_class.new(agent: agent, account: account, workflow_run: workflow_run)
    end

    before { workflow_service.clear }

    it 'isolates memory by workflow run' do
      workflow_service.store('workflow_key', 'workflow_value')

      expect(workflow_service.retrieve('workflow_key')).to eq('workflow_value')
      expect(service.retrieve('workflow_key')).to be_nil
    end
  end

  describe '#share_with_agent' do
    let(:target_agent) { create(:ai_agent, account: account) }

    it 'shares memory with another agent' do
      service.store('to_share', 'shared_value')
      service.share_with_agent(target_agent, 'shared_key', 'shared_value')

      target_service = described_class.new(agent: target_agent, account: account)
      shared = target_service.retrieve_shared(agent.id, 'shared_key')

      expect(shared).to eq('shared_value')
    end
  end

  describe '#persist_to_database' do
    it 'persists working memory to database' do
      service.store('to_persist', 'persistent_value')

      expect { service.persist_to_database('to_persist', importance: 0.8) }.not_to raise_error
    end
  end

  describe '#load_from_database' do
    before do
      service.store('key', 'value')
      service.persist_to_database('key')
      service.clear
    end

    it 'loads persisted memory back from database' do
      expect { service.load_from_database }.not_to raise_error
    end
  end
end
