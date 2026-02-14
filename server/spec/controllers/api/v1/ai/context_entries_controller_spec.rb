# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::Ai::ContextEntriesController, type: :controller do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: ['ai.context.read', 'ai.context.create', 'ai.context.update', 'ai.context.delete']) }
  let(:read_only_user) { create(:user, account: account, permissions: ['ai.context.read']) }
  let(:no_perms_user) { create(:user, account: account, permissions: []) }

  let(:context) { create(:ai_persistent_context, account: account, context_type: 'agent_memory') }
  let!(:entry) { create(:ai_context_entry, persistent_context: context) }

  before { sign_in_as_user(user) }

  # ============================================================================
  # AUTHENTICATION
  # ============================================================================

  describe 'authentication' do
    it 'returns 401 without token' do
      @request.env.delete('HTTP_AUTHORIZATION')
      get :index, params: { context_id: context.id }
      expect(response).to have_http_status(:unauthorized)
    end
  end

  # ============================================================================
  # AUTHORIZATION
  # ============================================================================

  describe 'authorization' do
    context 'without permissions' do
      before { sign_in_as_user(no_perms_user) }

      it 'returns 403 for index' do
        allow(Ai::ContextPersistenceService).to receive(:find_context).and_return(context)
        get :index, params: { context_id: context.id }
        expect(response).to have_http_status(:forbidden)
      end

      it 'returns 403 for show' do
        allow(Ai::ContextPersistenceService).to receive(:find_context).and_return(context)
        get :show, params: { context_id: context.id, id: entry.id }
        expect(response).to have_http_status(:forbidden)
      end

      it 'returns 403 for create' do
        allow(Ai::ContextPersistenceService).to receive(:find_context).and_return(context)
        post :create, params: { context_id: context.id, entry: { key: 'test', content_text: 'text' } }
        expect(response).to have_http_status(:forbidden)
      end

      it 'returns 403 for destroy' do
        allow(Ai::ContextPersistenceService).to receive(:find_context).and_return(context)
        delete :destroy, params: { context_id: context.id, id: entry.id }
        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'with read-only permissions' do
      before { sign_in_as_user(read_only_user) }

      it 'allows index access' do
        allow(Ai::ContextPersistenceService).to receive(:find_context).and_return(context)
        entries_result = Ai::ContextEntry.where(id: entry.id).page(1).per(20)
        allow(Ai::ContextPersistenceService).to receive(:list_entries).and_return(entries_result)

        get :index, params: { context_id: context.id }
        expect(response).to have_http_status(:ok)
      end

      it 'returns 403 for create' do
        allow(Ai::ContextPersistenceService).to receive(:find_context).and_return(context)
        post :create, params: { context_id: context.id, entry: { key: 'test', content_text: 'text' } }
        expect(response).to have_http_status(:forbidden)
      end

      it 'returns 403 for update' do
        allow(Ai::ContextPersistenceService).to receive(:find_context).and_return(context)
        patch :update, params: { context_id: context.id, id: entry.id, entry: { content_text: 'updated' } }
        expect(response).to have_http_status(:forbidden)
      end

      it 'returns 403 for delete' do
        allow(Ai::ContextPersistenceService).to receive(:find_context).and_return(context)
        delete :destroy, params: { context_id: context.id, id: entry.id }
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  # ============================================================================
  # INDEX
  # ============================================================================

  describe 'GET #index' do
    before do
      allow(Ai::ContextPersistenceService).to receive(:find_context).and_return(context)
    end

    it 'returns context entries' do
      entries_result = Ai::ContextEntry.where(id: entry.id).page(1).per(20)
      allow(Ai::ContextPersistenceService).to receive(:list_entries).and_return(entries_result)

      get :index, params: { context_id: context.id }
      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true
      expect(json_response['data']['entries']).to be_an(Array)
    end
  end

  # ============================================================================
  # SHOW
  # ============================================================================

  describe 'GET #show' do
    before do
      allow(Ai::ContextPersistenceService).to receive(:find_context).and_return(context)
    end

    it 'returns entry details' do
      get :show, params: { context_id: context.id, id: entry.id }
      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true
      expect(json_response['data']['entry']).to be_present
    end

    it 'returns 404 for non-existent entry' do
      get :show, params: { context_id: context.id, id: SecureRandom.uuid }
      expect(response).to have_http_status(:not_found)
    end
  end

  # ============================================================================
  # CREATE
  # ============================================================================

  describe 'POST #create' do
    before do
      allow(Ai::ContextPersistenceService).to receive(:find_context).and_return(context)
    end

    it 'creates a new entry' do
      new_entry = create(:ai_context_entry, persistent_context: context)
      allow(Ai::ContextPersistenceService).to receive(:add_entry).and_return(new_entry)

      post :create, params: {
        context_id: context.id,
        entry: { key: 'new_key', content_text: 'New content', entry_type: 'fact' }
      }
      expect(response).to have_http_status(:created)
      expect(json_response['success']).to be true
    end

    it 'returns error for validation failure' do
      allow(Ai::ContextPersistenceService).to receive(:add_entry)
        .and_raise(Ai::ContextPersistenceService::ValidationError, 'Key is required')

      post :create, params: {
        context_id: context.id,
        entry: { key: '', content_text: '' }
      }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  # ============================================================================
  # UPDATE
  # ============================================================================

  describe 'PATCH #update' do
    before do
      allow(Ai::ContextPersistenceService).to receive(:find_context).and_return(context)
    end

    it 'updates an entry' do
      allow(Ai::ContextPersistenceService).to receive(:update_entry).and_return(entry)

      patch :update, params: {
        context_id: context.id,
        id: entry.id,
        entry: { content_text: 'Updated content' }
      }
      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true
    end

    it 'returns error for validation failure' do
      allow(Ai::ContextPersistenceService).to receive(:update_entry)
        .and_raise(Ai::ContextPersistenceService::ValidationError, 'Invalid update')

      patch :update, params: {
        context_id: context.id,
        id: entry.id,
        entry: { content_text: '' }
      }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  # ============================================================================
  # DESTROY
  # ============================================================================

  describe 'DELETE #destroy' do
    before do
      allow(Ai::ContextPersistenceService).to receive(:find_context).and_return(context)
    end

    it 'deletes an entry' do
      allow(Ai::ContextPersistenceService).to receive(:delete_entry).and_return(true)

      delete :destroy, params: { context_id: context.id, id: entry.id }
      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true
    end
  end

  # ============================================================================
  # ARCHIVE / UNARCHIVE
  # ============================================================================

  describe 'POST #archive' do
    before do
      allow(Ai::ContextPersistenceService).to receive(:find_context).and_return(context)
    end

    it 'archives an entry' do
      post :archive, params: { context_id: context.id, id: entry.id }
      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true
    end
  end

  describe 'POST #unarchive' do
    let(:archived_entry) { create(:ai_context_entry, :archived, persistent_context: context) }

    before do
      allow(Ai::ContextPersistenceService).to receive(:find_context).and_return(context)
    end

    it 'unarchives an entry' do
      post :unarchive, params: { context_id: context.id, id: archived_entry.id }
      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true
    end
  end

  # ============================================================================
  # BOOST
  # ============================================================================

  describe 'POST #boost' do
    before do
      allow(Ai::ContextPersistenceService).to receive(:find_context).and_return(context)
    end

    it 'boosts entry importance' do
      post :boost, params: { context_id: context.id, id: entry.id, amount: 0.2 }
      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true
    end
  end

  # ============================================================================
  # HISTORY
  # ============================================================================

  describe 'GET #history' do
    before do
      allow(Ai::ContextPersistenceService).to receive(:find_context).and_return(context)
    end

    it 'returns entry version history' do
      get :history, params: { context_id: context.id, id: entry.id }
      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true
      expect(json_response['data']).to have_key('current_version')
    end
  end

  # ============================================================================
  # BULK CREATE
  # ============================================================================

  describe 'POST #bulk_create' do
    before do
      allow(Ai::ContextPersistenceService).to receive(:find_context).and_return(context)
    end

    it 'creates multiple entries' do
      new_entry = create(:ai_context_entry, persistent_context: context)
      allow(Ai::ContextPersistenceService).to receive(:add_entry).and_return(new_entry)

      post :bulk_create, params: {
        context_id: context.id,
        entries: [
          { key: 'key1', content_text: 'Content 1' },
          { key: 'key2', content_text: 'Content 2' }
        ]
      }
      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true
      expect(json_response['data']['total']).to eq(2)
    end
  end
end
