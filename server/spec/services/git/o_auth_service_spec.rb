# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Git::OAuthService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  describe 'GitHub OAuth' do
    let(:provider) do
      create(:git_provider, :github,
             oauth_config: {
               'client_id' => 'github_client_id',
               'client_secret' => 'github_client_secret',
               'redirect_uri' => 'https://app.example.com/oauth/github/callback',
               'scopes' => %w[repo user]
             })
    end
    let(:service) { described_class.new(provider, account) }

    describe '#authorization_url' do
      it 'generates GitHub authorization URL with correct parameters' do
        state = service.generate_state(user)
        url = service.authorization_url(state: state)

        expect(url).to start_with('https://github.com/login/oauth/authorize')
        expect(url).to include('client_id=github_client_id')
        expect(url).to include('scope=repo+user')
        expect(url).to include("state=#{CGI.escape(state)}")
      end

      it 'uses custom redirect_uri when provided' do
        url = service.authorization_url(redirect_uri: 'https://custom.example.com/callback')

        expect(url).to include('redirect_uri=https%3A%2F%2Fcustom.example.com%2Fcallback')
      end
    end

    describe '#generate_state' do
      it 'generates a valid base64-encoded state token' do
        state = service.generate_state(user)

        expect { Base64.urlsafe_decode64(state) }.not_to raise_error
        payload = JSON.parse(Base64.urlsafe_decode64(state))

        expect(payload['user_id']).to eq(user.id)
        expect(payload['account_id']).to eq(account.id)
        expect(payload['provider_id']).to eq(provider.id)
        expect(payload['timestamp']).to be_present
        expect(payload['nonce']).to be_present
      end
    end

    describe '#handle_callback' do
      let(:state) { service.generate_state(user) }

      context 'with valid code' do
        before do
          # Stub GitHub token exchange
          stub_request(:post, 'https://github.com/login/oauth/access_token')
            .with(
              body: hash_including(
                'client_id' => 'github_client_id',
                'client_secret' => 'github_client_secret',
                'code' => 'valid_auth_code'
              )
            )
            .to_return(
              status: 200,
              body: 'access_token=gho_test_token_123&token_type=bearer&scope=repo,user'
            )

          # Stub GitHub user info
          stub_request(:get, 'https://api.github.com/user')
            .with(headers: { 'Authorization' => 'Bearer gho_test_token_123' })
            .to_return(
              status: 200,
              body: { login: 'testuser', id: 123, avatar_url: 'https://github.com/avatar.png' }.to_json,
              headers: { 'Content-Type' => 'application/json' }
            )
        end

        it 'exchanges code for token and creates credential' do
          result = service.handle_callback(code: 'valid_auth_code', state: state)

          expect(result[:success]).to be true
          expect(result[:credential]).to be_persisted
          expect(result[:credential].external_username).to eq('testuser')
          expect(result[:credential].auth_type).to eq('oauth')
          expect(result[:credential].git_provider).to eq(provider)
          expect(result[:credential].account).to eq(account)
        end
      end

      context 'with invalid code' do
        before do
          stub_request(:post, 'https://github.com/login/oauth/access_token')
            .to_return(
              status: 200,
              body: 'error=bad_verification_code&error_description=The+code+passed+is+incorrect+or+expired.'
            )
        end

        it 'returns failure' do
          result = service.handle_callback(code: 'invalid_code', state: state)

          expect(result[:success]).to be false
          expect(result[:error]).to include('incorrect or expired')
        end
      end

      context 'with expired state' do
        it 'returns failure for expired state' do
          old_payload = {
            user_id: user.id,
            account_id: account.id,
            provider_id: provider.id,
            timestamp: 20.minutes.ago.to_i,
            nonce: SecureRandom.hex(16)
          }
          expired_state = Base64.urlsafe_encode64(old_payload.to_json)

          result = service.handle_callback(code: 'code', state: expired_state)

          expect(result[:success]).to be false
          expect(result[:error]).to eq('OAuth state has expired')
        end
      end

      context 'with provider mismatch' do
        let(:other_provider) { create(:git_provider, :gitlab) }

        it 'returns failure for mismatched provider' do
          wrong_state_payload = {
            user_id: user.id,
            account_id: account.id,
            provider_id: other_provider.id,
            timestamp: Time.current.to_i,
            nonce: SecureRandom.hex(16)
          }
          wrong_state = Base64.urlsafe_encode64(wrong_state_payload.to_json)

          result = service.handle_callback(code: 'code', state: wrong_state)

          expect(result[:success]).to be false
          expect(result[:error]).to eq('OAuth state provider mismatch')
        end
      end
    end
  end

  describe 'GitLab OAuth' do
    let(:provider) do
      create(:git_provider, :gitlab,
             web_base_url: 'https://gitlab.com',
             oauth_config: {
               'client_id' => 'gitlab_client_id',
               'client_secret' => 'gitlab_client_secret',
               'redirect_uri' => 'https://app.example.com/oauth/gitlab/callback',
               'scopes' => %w[api read_user]
             })
    end
    let(:service) { described_class.new(provider, account) }

    describe '#authorization_url' do
      it 'generates GitLab authorization URL with correct parameters' do
        state = service.generate_state(user)
        url = service.authorization_url(state: state)

        expect(url).to start_with('https://gitlab.com/oauth/authorize')
        expect(url).to include('client_id=gitlab_client_id')
        expect(url).to include('response_type=code')
        expect(url).to include('scope=api+read_user')
      end
    end

    describe '#handle_callback' do
      let(:state) { service.generate_state(user) }

      context 'with valid code' do
        before do
          # Stub GitLab token exchange
          stub_request(:post, 'https://gitlab.com/oauth/token')
            .with(
              body: hash_including(
                'client_id' => 'gitlab_client_id',
                'client_secret' => 'gitlab_client_secret',
                'code' => 'valid_auth_code',
                'grant_type' => 'authorization_code'
              )
            )
            .to_return(
              status: 200,
              body: {
                access_token: 'glpat_test_token',
                refresh_token: 'refresh_token_123',
                token_type: 'Bearer',
                expires_in: 7200,
                scope: 'api read_user'
              }.to_json,
              headers: { 'Content-Type' => 'application/json' }
            )

          # Stub GitLab user info
          stub_request(:get, 'https://gitlab.com/api/v4/user')
            .with(headers: { 'Authorization' => 'Bearer glpat_test_token' })
            .to_return(
              status: 200,
              body: { username: 'gitlabuser', id: 456, avatar_url: 'https://gitlab.com/avatar.png' }.to_json,
              headers: { 'Content-Type' => 'application/json' }
            )
        end

        it 'exchanges code for token and creates credential with expiration' do
          result = service.handle_callback(code: 'valid_auth_code', state: state)

          expect(result[:success]).to be true
          expect(result[:credential]).to be_persisted
          expect(result[:credential].external_username).to eq('gitlabuser')
          expect(result[:credential].expires_at).to be_present
          expect(result[:credential].expires_at).to be > Time.current
        end
      end
    end
  end

  describe 'Gitea OAuth' do
    let(:provider) do
      create(:git_provider, :gitea,
             api_base_url: 'https://git.example.com/api/v1',
             web_base_url: 'https://git.example.com',
             oauth_config: {
               'client_id' => 'gitea_client_id',
               'client_secret' => 'gitea_client_secret',
               'redirect_uri' => 'https://app.example.com/oauth/gitea/callback',
               'scopes' => %w[read:user]
             })
    end
    let(:service) { described_class.new(provider, account) }

    describe '#authorization_url' do
      it 'generates Gitea authorization URL with correct parameters' do
        state = service.generate_state(user)
        url = service.authorization_url(state: state)

        expect(url).to start_with('https://git.example.com/login/oauth/authorize')
        expect(url).to include('client_id=gitea_client_id')
        expect(url).to include('response_type=code')
      end

      context 'without web_base_url configured' do
        let(:provider) do
          create(:git_provider, provider_type: 'gitea',
                 api_base_url: 'https://git.example.com/api/v1',
                 web_base_url: nil)
        end

        it 'raises an error' do
          expect { service.authorization_url }.to raise_error(
            GitOAuthService::OAuthError,
            /Gitea provider requires web_base_url/
          )
        end
      end
    end

    describe '#handle_callback' do
      let(:state) { service.generate_state(user) }

      context 'with valid code' do
        before do
          # Stub Gitea token exchange
          stub_request(:post, 'https://git.example.com/login/oauth/access_token')
            .with(
              body: hash_including(
                'client_id' => 'gitea_client_id',
                'client_secret' => 'gitea_client_secret',
                'code' => 'valid_auth_code',
                'grant_type' => 'authorization_code'
              )
            )
            .to_return(
              status: 200,
              body: {
                access_token: 'gitea_token_xyz',
                refresh_token: 'gitea_refresh',
                token_type: 'bearer'
              }.to_json,
              headers: { 'Content-Type' => 'application/json' }
            )

          # Stub Gitea user info (api_base_url already includes /api/v1)
          stub_request(:get, 'https://git.example.com/api/v1/user')
            .with(headers: { 'Authorization' => 'token gitea_token_xyz' })
            .to_return(
              status: 200,
              body: { login: 'giteauser', id: 789, avatar_url: 'https://git.example.com/avatar.png' }.to_json,
              headers: { 'Content-Type' => 'application/json' }
            )
        end

        it 'exchanges code for token and creates credential' do
          result = service.handle_callback(code: 'valid_auth_code', state: state)

          expect(result[:success]).to be true
          expect(result[:credential]).to be_persisted
          expect(result[:credential].external_username).to eq('giteauser')
        end
      end
    end
  end

  describe 'unsupported provider type' do
    let(:provider) do
      build(:git_provider, provider_type: 'github').tap do |p|
        allow(p).to receive(:provider_type).and_return('unsupported')
      end
    end
    let(:service) { described_class.new(provider, account) }

    it 'raises error for authorization_url' do
      expect { service.authorization_url }.to raise_error(
        GitOAuthService::OAuthError,
        /OAuth not supported for provider type/
      )
    end
  end

  describe 'invalid state handling' do
    let(:provider) { create(:git_provider, :github) }
    let(:service) { described_class.new(provider, account) }

    it 'handles malformed state gracefully' do
      result = service.handle_callback(code: 'code', state: 'not_valid_base64!')

      expect(result[:success]).to be false
      expect(result[:error]).to eq('Invalid OAuth state')
    end

    it 'handles invalid JSON in state' do
      invalid_state = Base64.urlsafe_encode64('not json')

      result = service.handle_callback(code: 'code', state: invalid_state)

      expect(result[:success]).to be false
      expect(result[:error]).to eq('Invalid OAuth state')
    end
  end
end
