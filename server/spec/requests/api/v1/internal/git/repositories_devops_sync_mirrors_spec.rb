# frozen_string_literal: true

require 'rails_helper'

# A devops-provider sync rewrites a repository's metadata from what the
# provider reports. The operator's push-mirror list (read by
# dev_merge_increment) is not the provider's to rewrite: a sync that dropped it
# would turn a two-remote merge into a one-remote "success".
RSpec.describe 'Api::V1::Internal::Git::Repositories devops sync keeps operator metadata', type: :request do
  let(:account) { create(:account) }
  let(:provider) { create(:devops_provider, account: account) }
  let(:internal_worker) { create(:worker, account: account) }
  let(:headers) do
    { 'X-Forwarded-Tls-Client-Cert-Info' => CGI.escape(%(Subject="CN=#{internal_worker.node_instance_id}")) }
  end
  let(:mirror_ids) { [ SecureRandom.uuid ] }
  let!(:repository) do
    create(:git_repository, account: account, credential: nil, provider: provider, origin: 'devops',
                            external_id: 'ext-1', full_name: 'owner/platform',
                            metadata: { Devops::GitRepository::PUSH_MIRRORS_KEY => mirror_ids, 'stale' => 'x' })
  end

  def sync(metadata)
    post api_v1_internal_git_repositories_path, headers: headers, as: :json,
         params: { devops_provider_id: provider.id,
                   repository: { external_id: 'ext-1', name: 'platform', full_name: 'owner/platform',
                                 owner: 'owner', metadata: metadata }.compact }
  end

  it 'keeps push_mirror_repository_ids when the provider reports other metadata' do
    sync({ 'topics_from_provider' => [ 'a' ] })

    expect(response).to have_http_status(:ok)
    expect(repository.reload.metadata).to include(Devops::GitRepository::PUSH_MIRRORS_KEY => mirror_ids,
                                                  'topics_from_provider' => [ 'a' ])
    expect(repository.metadata).not_to have_key('stale')
  end

  it 'keeps it when the provider reports no metadata at all' do
    sync(nil)

    expect(repository.reload.push_mirror_repository_ids).to eq(mirror_ids)
  end

  it 'does not let the provider write the list' do
    sync({ Devops::GitRepository::PUSH_MIRRORS_KEY => [ SecureRandom.uuid ] })

    expect(repository.reload.push_mirror_repository_ids).to eq(mirror_ids)
  end
end
