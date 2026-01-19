# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::Internal::Git::CredentialsController, type: :controller do
  let(:account) { create(:account) }
  let(:provider) { create(:git_provider, :github) }
  let(:credential) do
    create(:git_provider_credential, :healthy,
           provider: provider,
           account: account,
           external_username: 'testuser')
  end

  before do
    @request.headers['Content-Type'] = 'application/json'
    @request.headers['Accept'] = 'application/json'
    set_service_auth_headers
  end

  # =============================================================================
  # SHOW
  # =============================================================================

  describe 'GET #show' do
    it 'returns credential details' do
      get :show, params: { id: credential.id }

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
      expect(json['data']['id']).to eq(credential.id)
      expect(json['data']['external_username']).to eq('testuser')
    end

    it 'includes provider information' do
      get :show, params: { id: credential.id }

      json = JSON.parse(response.body)
      expect(json['data']['provider']['id']).to eq(provider.id)
      expect(json['data']['provider']['provider_type']).to eq('github')
    end

    it 'includes health status' do
      get :show, params: { id: credential.id }

      json = JSON.parse(response.body)
      expect(json['data']['healthy']).to be true
      expect(json['data']['can_be_used']).to be true
    end

    it 'includes usage statistics' do
      credential.update!(success_count: 50, failure_count: 2)

      get :show, params: { id: credential.id }

      json = JSON.parse(response.body)
      expect(json['data']['success_count']).to eq(50)
      expect(json['data']['failure_count']).to eq(2)
    end

    it 'returns not found for non-existent credential' do
      get :show, params: { id: SecureRandom.uuid }

      expect(response).to have_http_status(:not_found)
      json = JSON.parse(response.body)
      expect(json['success']).to be false
      expect(json['error']).to eq('Credential not found')
    end

    context 'with unhealthy credential' do
      let(:unhealthy_credential) do
        create(:git_provider_credential, :unhealthy,
               provider: provider,
               account: account)
      end

      it 'reports unhealthy status' do
        get :show, params: { id: unhealthy_credential.id }

        json = JSON.parse(response.body)
        expect(json['data']['healthy']).to be false
        expect(json['data']['consecutive_failures']).to be > 0
      end
    end
  end

  # =============================================================================
  # DECRYPTED
  # =============================================================================

  describe 'GET #decrypted' do
    it 'returns decrypted credentials' do
      get :decrypted, params: { id: credential.id }

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
      expect(json['data']['credentials']).to be_present
      expect(json['data']['credentials']).to include('access_token')
    end

    it 'includes auth type' do
      get :decrypted, params: { id: credential.id }

      json = JSON.parse(response.body)
      expect(json['data']['auth_type']).to eq('personal_access_token')
    end

    it 'includes provider API URLs' do
      get :decrypted, params: { id: credential.id }

      json = JSON.parse(response.body)
      expect(json['data']['provider']['provider_type']).to eq('github')
      expect(json['data']['provider']['api_base_url']).to be_present
    end

    context 'when decryption fails' do
      before do
        allow_any_instance_of(Devops::GitProviderCredential).to receive(:decrypt_credentials)
          .and_raise(StandardError, 'Decryption error')
      end

      it 'returns error' do
        get :decrypted, params: { id: credential.id }

        expect(response).to have_http_status(:internal_server_error)
        json = JSON.parse(response.body)
        expect(json['success']).to be false
        expect(json['error']).to eq('Failed to decrypt credentials')
      end
    end

    it 'returns not found for non-existent credential' do
      get :decrypted, params: { id: SecureRandom.uuid }

      expect(response).to have_http_status(:not_found)
    end
  end

  # =============================================================================
  # AUTHENTICATION
  # =============================================================================

  describe 'authentication' do
    it 'requires service token for show' do
      @request.env.delete('HTTP_AUTHORIZATION')
      get :show, params: { id: credential.id }

      expect(response).to have_http_status(:unauthorized)
    end

    it 'requires service token for decrypted' do
      @request.env.delete('HTTP_AUTHORIZATION')
      get :decrypted, params: { id: credential.id }

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
