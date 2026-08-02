# frozen_string_literal: true

require 'rails_helper'

# Found live on ops-hub 2026-08-02. The indexer and the searcher keyed their
# knowledge base DIFFERENTLY, so indexed data was unreachable:
#
#   indexer  -> this controller resolved the repo with find_by(id:) ONLY, so a
#               name/full_name silently resolved to nil and fell through to the
#               base_path branch, creating "Codebase: <basename>"
#   searcher -> CodebaseContextResolvable#resolve_repository accepts id, name
#               OR full_name and looks the KB up by git_repository_id
#
# Result: `code_bulk_index repository_id: "powernode/powernode-platform"`
# produced 16k+ orphan nodes that no repository-scoped search could ever see,
# with no error anywhere. The silence is the defect — an explicit repository_id
# that doesn't resolve must not quietly index somewhere else.
RSpec.describe 'Api::V1::Internal::Codebase', type: :request do
  let(:account) { create(:account) }
  let(:internal_worker) { create(:worker, account: account) }
  let(:internal_headers) do
    { 'X-Forwarded-Tls-Client-Cert-Info' => CGI.escape(%(Subject="CN=#{internal_worker.node_instance_id}")) }
  end
  let(:base_path) { Dir.mktmpdir }

  after { FileUtils.remove_entry(base_path) if File.directory?(base_path) }

  before do
    allow_any_instance_of(Ai::Codebase::IndexingService)
      .to receive(:index).and_return({ success: true, indexed_files: 0 })
  end

  def post_index(repository_id:)
    post '/api/v1/internal/codebase/index',
         params: { account_id: account.id, base_path: base_path, repository_id: repository_id },
         headers: internal_headers, as: :json
  end

  describe 'POST /api/v1/internal/codebase/index' do
    let!(:repository) do
      create(:git_repository, account: account,
                              name: 'powernode-platform',
                              full_name: 'powernode/powernode-platform')
    end

    it 'keys the knowledge base to the repository when given a full_name' do
      post_index(repository_id: 'powernode/powernode-platform')

      expect(response).to have_http_status(:success)
      kbs = account.ai_knowledge_bases.where(git_repository_id: repository.id)
      expect(kbs.count).to eq(1)
      expect(account.ai_knowledge_bases.where(name: "Codebase: #{File.basename(base_path)}")).to be_empty
    end

    it 'keys the knowledge base to the repository when given a bare name' do
      post_index(repository_id: 'powernode-platform')

      expect(response).to have_http_status(:success)
      expect(account.ai_knowledge_bases.where(git_repository_id: repository.id).count).to eq(1)
    end

    it 'still accepts the repository id' do
      post_index(repository_id: repository.id)

      expect(response).to have_http_status(:success)
      expect(account.ai_knowledge_bases.where(git_repository_id: repository.id).count).to eq(1)
    end

    it 'fails closed when an explicit repository_id resolves to nothing' do
      post_index(repository_id: 'no-such-repo')

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body['error'] || response.parsed_body['message']).to match(/repository/i)
      # The orphan-index defect: it must NOT quietly index under base_path.
      expect(account.ai_knowledge_bases.count).to eq(0)
    end

    it 'still keys by base_path when no repository_id is supplied at all' do
      post '/api/v1/internal/codebase/index',
           params: { account_id: account.id, base_path: base_path },
           headers: internal_headers, as: :json

      expect(response).to have_http_status(:success)
      expect(account.ai_knowledge_bases.where(name: "Codebase: #{File.basename(base_path)}").count).to eq(1)
    end
  end
end
