# frozen_string_literal: true

require 'rails_helper'

# IMP-3a19f9c93eac — several git providers, each reachable over HTTPS (token)
# and/or SSH (key). The private key lives only in the encrypted credential
# store: it is never returned, never logged, and every key operation is audited
# inside its own transaction so an unauditable write is not stored.
RSpec.describe 'Api::V1::Git::Providers SSH access', type: :request do
  let(:account) { create(:account) }
  let(:user) do
    create(:user, account: account, permissions: %w[
      git.providers.read git.providers.create git.providers.delete git.credentials.read git.credentials.create
      git.credentials.update git.credentials.delete
    ])
  end
  let(:headers) { auth_headers_for(user) }

  # Obviously fake material; the PEM markers are assembled at runtime so no
  # key-shaped literal sits in the source.
  let(:fake_body) { Base64.strict_encode64('not-a-real-key-placeholder-material') }
  let(:fake_private_key) do
    label = [ 'OPENSSH', 'PRIVATE', 'KEY' ].join(' ')
    "-----BEGIN #{label}-----\n#{fake_body}\n-----END #{label}-----\n"
  end
  let(:fake_public_key) { "ssh-ed25519 #{Base64.strict_encode64('fake-public-blob-for-spec')} spec@example.test" }
  let(:fake_token) { 'fake-token-not-real-0001' }

  before do
    allow_any_instance_of(Devops::Git::ProviderTestService).to receive(:test_connection).and_return({ success: false, error: 'stubbed' })
  end

  def create_provider(name:, type: 'gitea', **extra)
    post '/api/v1/git/providers',
         params: { provider: { name: name, provider_type: type, api_base_url: 'https://git.example.test/api/v1',
                               metadata: { ssh: { host: 'git.example.test', port: 2222 } } }.merge(extra) },
         headers: headers, as: :json
    expect(response).to have_http_status(:created)
    json_response_data['provider']['id']
  end

  def post_credential(provider_id, **credential)
    post "/api/v1/git/providers/#{provider_id}/credentials", params: { credential: credential }, headers: headers, as: :json
  end

  def https_credential
    { name: 'HTTPS token', auth_type: 'personal_access_token', credentials: { token: fake_token } }
  end

  def ssh_credential(**over)
    { name: 'SSH key', auth_type: 'ssh_key', is_default: false,
      credentials: { private_key: fake_private_key, public_key: fake_public_key } }.merge(over)
  end

  it 'holds both an HTTPS token and an SSH key on one provider, the token staying the default' do
    provider_id = create_provider(name: 'Forge One')

    post_credential(provider_id, **https_credential)
    expect(response).to have_http_status(:created)
    post_credential(provider_id, **ssh_credential)
    expect(response).to have_http_status(:created)

    creds = Devops::GitProviderCredential.where(git_provider_id: provider_id)
    expect(creds.map(&:auth_type)).to contain_exactly('personal_access_token', 'ssh_key')
    expect(creds.find_by(is_default: true).auth_type).to eq('personal_access_token')
  end

  it 'never makes an SSH key the API default, even when it is stored first' do
    provider_id = create_provider(name: 'Forge Two')

    post_credential(provider_id, **ssh_credential(is_default: true))

    expect(response).to have_http_status(:created)
    expect(Devops::GitProviderCredential.find_by(git_provider_id: provider_id).is_default).to be(false)
    expect(Devops::GitProvider.find(provider_id).default_credential_for_account(account)).to be_nil
  end

  it 'never returns the private key and exposes only the public half and fingerprint' do
    provider_id = create_provider(name: 'Forge Three')

    post_credential(provider_id, **ssh_credential)

    expect(response.body).not_to include(fake_body)
    expect(response.body).not_to include('PRIVATE KEY')
    credential = json_response_data['credential']
    expect(credential['ssh']).to include('public_key' => fake_public_key)
    expect(credential['ssh']['fingerprint']).to match(/\ASHA256:/)

    get "/api/v1/git/providers/#{provider_id}/credentials", headers: headers
    expect(response.body).not_to include(fake_body)
  end

  it 'rejects a value that is not a private key' do
    provider_id = create_provider(name: 'Forge Four')

    post_credential(provider_id, **ssh_credential(credentials: { private_key: 'just some text' }))

    expect(response).to have_http_status(:unprocessable_content)
    expect(Devops::GitProviderCredential.where(git_provider_id: provider_id)).to be_empty
  end

  it 'supports several providers, each with its own access methods' do
    first = create_provider(name: 'Gitea Home')
    second = create_provider(name: 'GitHub Work', type: 'github', api_base_url: 'https://api.github.com')

    post_credential(first, **https_credential)
    post_credential(first, **ssh_credential)
    post_credential(second, **ssh_credential(name: 'Work SSH'))

    expect(account.git_providers.count).to eq(2)
    expect(Devops::GitProviderCredential.where(git_provider_id: first).count).to eq(2)
    expect(Devops::GitProviderCredential.where(git_provider_id: second).pluck(:auth_type)).to eq([ 'ssh_key' ])
  end

  describe 'auditing' do
    it 'audits the key creation without the key, inside the same transaction' do
      provider_id = create_provider(name: 'Forge Five')

      expect { post_credential(provider_id, **ssh_credential) }.to change {
        AuditLog.where(action: 'git.credentials.ssh_key.create').count
      }.by(1)

      log = AuditLog.where(action: 'git.credentials.ssh_key.create').last
      expect(log.metadata.to_json).not_to include(fake_body)
      expect(log.metadata['fingerprint']).to match(/\ASHA256:/)
      expect(log.new_values.to_json).not_to include(fake_body)
    end

    it 'fails closed: nothing is stored when the audit write fails' do
      provider_id = create_provider(name: 'Forge Six')
      allow(AuditLog).to receive(:log_action).and_raise(ActiveRecord::RecordInvalid.new(AuditLog.new))

      expect { post_credential(provider_id, **ssh_credential) }
        .not_to change(Devops::GitProviderCredential, :count)

      expect(response).to have_http_status(:service_unavailable)
      expect(response.body).not_to include(fake_body)
    end

    it 'audits the key removal and fails closed on it too' do
      provider_id = create_provider(name: 'Forge Seven')
      post_credential(provider_id, **https_credential)
      post_credential(provider_id, **ssh_credential)
      ssh_id = json_response_data['credential']['id']

      allow(AuditLog).to receive(:log_action).and_raise(ActiveRecord::RecordInvalid.new(AuditLog.new))
      expect { delete "/api/v1/git/providers/#{provider_id}/credentials/#{ssh_id}", headers: headers }
        .not_to change(Devops::GitProviderCredential, :count)
      expect(response).to have_http_status(:service_unavailable)

      allow(AuditLog).to receive(:log_action).and_call_original
      expect { delete "/api/v1/git/providers/#{provider_id}/credentials/#{ssh_id}", headers: headers }
        .to change(Devops::GitProviderCredential, :count).by(-1)
      expect(AuditLog.where(action: 'git.credentials.ssh_key.delete').count).to eq(1)
    end
  end

  describe 'DELETE /api/v1/git/providers/:id (removing a provider the wizard added)' do
    it 'removes the provider with both credentials and audits the key removal' do
      provider_id = create_provider(name: 'Forge Eight')
      post_credential(provider_id, **https_credential)
      post_credential(provider_id, **ssh_credential)

      expect { delete "/api/v1/git/providers/#{provider_id}", headers: headers }
        .to change(Devops::GitProviderCredential, :count).by(-2)

      expect(response).to have_http_status(:ok)
      expect(Devops::GitProvider.where(id: provider_id)).to be_empty
      expect(AuditLog.where(action: 'git.credentials.ssh_key.delete').count).to eq(1)
    end

    it 'fails closed: keeps the provider and its keys when the key removal cannot be audited' do
      provider_id = create_provider(name: 'Forge Nine')
      post_credential(provider_id, **https_credential)
      post_credential(provider_id, **ssh_credential)
      allow(AuditLog).to receive(:log_action).and_raise(ActiveRecord::RecordInvalid.new(AuditLog.new))

      expect { delete "/api/v1/git/providers/#{provider_id}", headers: headers }
        .not_to change(Devops::GitProviderCredential, :count)

      expect(response).to have_http_status(:service_unavailable)
      expect(Devops::GitProvider.where(id: provider_id)).to exist
    end
  end

  describe 'GET /api/v1/git/providers/catalog' do
    it 'serves per-type defaults including SSH host and port, and no secrets' do
      get '/api/v1/git/providers/catalog', headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      items = json_response_data['items']
      expect(items.map { |i| i['provider_type'] }).to include('github', 'gitlab', 'gitea')
      github = items.find { |i| i['provider_type'] == 'github' }
      expect(github).to include('web_base_url' => 'https://github.com', 'ssh_host' => 'github.com', 'ssh_port' => 22)
      expect(response.body).not_to match(/token|private_key/i)
    end
  end
end
