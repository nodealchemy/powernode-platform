# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Ai::AgentMemory', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: [ 'ai.memory.read', 'ai.memory.write' ]) }
  let(:read_only_user) { create(:user, account: account, permissions: [ 'ai.memory.read' ]) }
  let(:manage_user) { create(:user, account: account, permissions: [ 'ai.memory.read', 'ai.memory.write', 'ai.memory.manage' ]) }
  let(:regular_user) { create(:user, account: account, permissions: []) }
  let(:headers) { auth_headers_for(user) }

  # Create test agent using factory
  let(:test_agent) { create(:ai_agent, account: account) }

  # Mock context - we don't create real persistent contexts since we're mocking service calls
  let(:test_context) do
    instance_double(
      Ai::PersistentContext,
      id: SecureRandom.uuid,
      account: account,
      context_type: 'agent_memory'
    )
  end

  let(:test_entry) do
    instance_double(
      Ai::ContextEntry,
      entry_key: 'test_key',
      entry_type: 'memory',
      content: { data: 'test value' },
      content_text: 'test value',
      importance_score: 0.8
    )
  end

  describe 'GET /api/v1/ai/agents/:agent_id/memory' do
    let(:mock_entries) do
      double(
        map: [],
        current_page: 1,
        total_pages: 1,
        total_count: 0,
        limit_value: 20
      )
    end

    before do
      allow(Ai::ContextPersistenceService).to receive(:get_agent_memory)
        .and_return(test_context)
      allow(test_context).to receive(:context_summary).and_return({})
      allow(test_context).to receive_message_chain(:context_entries, :active, :order, :page, :per)
        .and_return(mock_entries)
    end

    context 'with ai.memory.read permission' do
      it 'returns agent memory entries' do
        get "/api/v1/ai/agents/#{test_agent.id}/memory",
            headers: headers,
            as: :json

        expect_success_response
        data = json_response_data
        expect(data).to have_key('memory')
        expect(data).to have_key('entries')
        expect(data).to have_key('pagination')
      end
    end

    context 'when no memory context exists' do
      before do
        allow(Ai::ContextPersistenceService).to receive(:get_agent_memory)
          .and_return(nil)
      end

      it 'returns empty memory response' do
        get "/api/v1/ai/agents/#{test_agent.id}/memory",
            headers: headers,
            as: :json

        expect_success_response
        data = json_response_data
        expect(data['memory']).to be_nil
        expect(data['entries']).to eq([])
        expect(data['message']).to eq('No memory context exists for this agent')
      end
    end

    context 'without permission' do
      it 'returns forbidden error' do
        get "/api/v1/ai/agents/#{test_agent.id}/memory",
            headers: auth_headers_for(regular_user),
            as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'GET /api/v1/ai/agents/:agent_id/memory/:key' do
    before do
      allow(Ai::ContextPersistenceService).to receive(:recall_memory)
        .and_return({ data: 'test value' })
    end

    context 'with permission' do
      it 'returns memory value for key' do
        get "/api/v1/ai/agents/#{test_agent.id}/memory/test_key",
            headers: headers,
            as: :json

        expect_success_response
        data = json_response_data
        expect(data['key']).to eq('test_key')
        expect(data).to have_key('value')
      end
    end

    context 'when key does not exist' do
      before do
        allow(Ai::ContextPersistenceService).to receive(:recall_memory)
          .and_return(nil)
      end

      it 'returns not found error' do
        get "/api/v1/ai/agents/#{test_agent.id}/memory/nonexistent",
            headers: headers,
            as: :json

        expect_error_response('Memory entry not found', 404)
      end
    end
  end

  describe 'POST /api/v1/ai/agents/:agent_id/memory' do
    let(:mock_entry) { double(entry_summary: { key: 'test_key', type: 'memory', value: 'test value' }) }

    before do
      allow(Ai::ContextPersistenceService).to receive(:store_memory)
        .and_return(mock_entry)
    end

    context 'with ai.memory.write permission' do
      it 'creates memory entry' do
        post "/api/v1/ai/agents/#{test_agent.id}/memory",
             params: {
               memory: {
                 key: 'test_key',
                 value: { data: 'test value' },
                 type: 'memory'
               }
             },
             headers: headers,
             as: :json

        expect(response).to have_http_status(:created)
        expect_success_response
        data = json_response_data
        expect(data).to have_key('entry')
      end
    end

    context 'with validation error' do
      before do
        allow(Ai::ContextPersistenceService).to receive(:store_memory)
          .and_raise(Ai::ContextPersistenceService::ValidationError, 'Invalid key')
      end

      it 'returns validation error' do
        post "/api/v1/ai/agents/#{test_agent.id}/memory",
             params: { memory: { key: '', value: 'test' } },
             headers: headers,
             as: :json

        expect_error_response('Invalid key', 422)
      end
    end

    context 'without permission' do
      it 'returns forbidden error' do
        post "/api/v1/ai/agents/#{test_agent.id}/memory",
             params: { memory: { key: 'test', value: 'test' } },
             headers: auth_headers_for(read_only_user),
             as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'PATCH /api/v1/ai/agents/:agent_id/memory/:key' do
    let(:mock_entry) { double(entry_summary: { key: 'test_key', type: 'memory', value: 'updated value' }) }

    before do
      allow(Ai::ContextPersistenceService).to receive(:store_memory)
        .and_return(mock_entry)
    end

    context 'with permission' do
      it 'updates memory entry' do
        patch "/api/v1/ai/agents/#{test_agent.id}/memory/test_key",
              params: {
                memory: {
                  value: { data: 'updated value' }
                }
              },
              headers: headers,
              as: :json

        expect_success_response
        data = json_response_data
        expect(data).to have_key('entry')
      end
    end
  end

  describe 'DELETE /api/v1/ai/agents/:agent_id/memory/:key' do
    before do
      allow(Ai::ContextPersistenceService).to receive(:get_agent_memory)
        .and_return(test_context)
      allow(Ai::ContextPersistenceService).to receive(:delete_entry)
        .and_return(true)
    end

    context 'with permission' do
      it 'deletes memory entry' do
        delete "/api/v1/ai/agents/#{test_agent.id}/memory/test_key",
               headers: headers,
               as: :json

        expect_success_response
        data = json_response_data
        expect(data['message']).to eq('Memory entry deleted')
      end
    end

    context 'when entry not found' do
      before do
        allow(Ai::ContextPersistenceService).to receive(:delete_entry)
          .and_raise(Ai::ContextPersistenceService::NotFoundError)
      end

      it 'returns not found error' do
        delete "/api/v1/ai/agents/#{test_agent.id}/memory/nonexistent",
               headers: headers,
               as: :json

        expect_error_response('Memory entry not found', 404)
      end
    end
  end

  describe 'POST /api/v1/ai/agents/:agent_id/memory/search' do
    let(:mock_memories) { [] }

    before do
      allow(Ai::ContextPersistenceService).to receive(:get_relevant_memories)
        .and_return(mock_memories)
      allow(mock_memories).to receive(:map).and_return([])
    end

    context 'with permission' do
      it 'searches memories' do
        post "/api/v1/ai/agents/#{test_agent.id}/memory/search",
             params: { q: 'test query', limit: 5 },
             headers: headers,
             as: :json

        expect_success_response
        data = json_response_data
        expect(data).to have_key('memories')
      end
    end
  end

  describe 'POST /api/v1/ai/agents/:agent_id/memory/clear' do
    let(:mock_entries) { double(count: 5, destroy_all: true) }

    before do
      allow(Ai::ContextPersistenceService).to receive(:get_agent_memory)
        .and_return(test_context)
      allow(test_context).to receive(:context_entries).and_return(mock_entries)
    end

    context 'with ai.memory.manage permission' do
      it 'clears all memory entries' do
        post "/api/v1/ai/agents/#{test_agent.id}/memory/clear",
             headers: auth_headers_for(manage_user),
             as: :json

        expect_success_response
        data = json_response_data
        expect(data['message']).to eq('Memory cleared')
        expect(data['cleared']).to eq(5)
      end
    end

    context 'when no memory exists' do
      before do
        allow(Ai::ContextPersistenceService).to receive(:get_agent_memory)
          .and_return(nil)
      end

      it 'returns success with zero cleared' do
        post "/api/v1/ai/agents/#{test_agent.id}/memory/clear",
             headers: auth_headers_for(manage_user),
             as: :json

        expect_success_response
        data = json_response_data
        expect(data['message']).to eq('No memory to clear')
        expect(data['cleared']).to eq(0)
      end
    end

    context 'without permission' do
      it 'returns forbidden error' do
        post "/api/v1/ai/agents/#{test_agent.id}/memory/clear",
             headers: headers,
             as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'GET /api/v1/ai/agents/:agent_id/memory/stats' do
    context 'when memory exists' do
      before do
        allow(Ai::ContextPersistenceService).to receive(:get_agent_memory)
          .and_return(test_context)
        allow_any_instance_of(Ai::Memory::MaintenanceService).to receive(:context_health)
          .and_return(entry_count: 10, avg_importance: 0.7)
      end

      it 'returns memory statistics' do
        get "/api/v1/ai/agents/#{test_agent.id}/memory/stats",
            headers: headers,
            as: :json

        expect_success_response
        data = json_response_data
        expect(data['stats']).to include(
          'has_memory' => true,
          'entry_count' => 10
        )
      end
    end

    context 'when no memory exists' do
      before do
        allow(Ai::ContextPersistenceService).to receive(:get_agent_memory)
          .and_return(nil)
      end

      it 'returns empty stats' do
        get "/api/v1/ai/agents/#{test_agent.id}/memory/stats",
            headers: headers,
            as: :json

        expect_success_response
        data = json_response_data
        expect(data['stats']).to include(
          'entry_count' => 0,
          'has_memory' => false
        )
      end
    end
  end

  describe 'POST /api/v1/ai/agents/:agent_id/memory/sync' do
    let(:source_context) do
      instance_double(
        Ai::PersistentContext,
        id: SecureRandom.uuid,
        account: account,
        context_type: 'agent_memory'
      )
    end

    before do
      allow(Ai::PersistentContext).to receive(:find_by).and_return(source_context)
      allow(Ai::ContextPersistenceService).to receive(:get_agent_memory)
        .and_return(test_context)
      allow_any_instance_of(Ai::Memory::MaintenanceService).to receive(:sync_context)
        .and_return({ synced: 5 })
    end

    context 'with ai.memory.manage permission' do
      it 'syncs memory from source context' do
        post "/api/v1/ai/agents/#{test_agent.id}/memory/sync",
             params: { source_context_id: source_context.id },
             headers: auth_headers_for(manage_user),
             as: :json

        expect_success_response
        data = json_response_data
        expect(data['synced']).to eq(5)
        expect(data['message']).to include('Synced 5 entries')
      end
    end

    context 'when source context not found' do
      before do
        allow(Ai::PersistentContext).to receive(:find_by).and_return(nil)
      end

      it 'returns not found error' do
        post "/api/v1/ai/agents/#{test_agent.id}/memory/sync",
             params: { source_context_id: SecureRandom.uuid },
             headers: auth_headers_for(manage_user),
             as: :json

        expect_error_response('Source context not found', 404)
      end
    end
  end
end
