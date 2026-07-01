# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Internal::Git::Repositories#sync_all_pipelines", type: :request do
  let(:account) { create(:account) }
  let(:git_provider) { create(:git_provider, :github) }
  let(:credential) { create(:git_provider_credential, account: account, provider: git_provider) }
  let(:internal_worker) { create(:worker, account: account) }
  let(:headers) { { "X-Forwarded-Tls-Client-Cert-Info" => CGI.escape(%(Subject="CN=#{internal_worker.node_instance_id}")) } }

  it "enqueues a PipelineSyncJob for each active repo with a credential" do
    r1 = create(:git_repository, credential: credential, account: account, is_archived: false)
    r2 = create(:git_repository, credential: credential, account: account, is_archived: false)
    create(:git_repository, credential: credential, account: account, is_archived: true) # archived → excluded

    calls = []
    allow(WorkerJobService).to receive(:enqueue_job) { |klass, opts| calls << [klass, opts] }

    post "/api/v1/internal/git/repositories/sync_all_pipelines", headers: headers

    expect(response).to have_http_status(:ok)
    data = JSON.parse(response.body)["data"] || JSON.parse(response.body)
    expect(data["enqueued"]).to eq(2)
    expect(calls.map(&:first)).to all(eq("Git::PipelineSyncJob"))
    expect(calls.map { |_, o| o[:args] }).to contain_exactly([ r1.id ], [ r2.id ])
  end

  it "does not enqueue for a repo whose credential is inactive (proactive pause)" do
    active_repo = create(:git_repository, credential: credential, account: account, is_archived: false)
    inactive_credential = create(:git_provider_credential, :inactive, account: account, provider: git_provider)
    create(:git_repository, credential: inactive_credential, account: account, is_archived: false)

    calls = []
    allow(WorkerJobService).to receive(:enqueue_job) { |klass, opts| calls << [klass, opts] }

    post "/api/v1/internal/git/repositories/sync_all_pipelines", headers: headers

    expect(response).to have_http_status(:ok)
    data = JSON.parse(response.body)["data"] || JSON.parse(response.body)
    expect(data["enqueued"]).to eq(1)
    expect(calls.map { |_, o| o[:args] }).to contain_exactly([ active_repo.id ])
  end

  it "requires worker auth" do
    post "/api/v1/internal/git/repositories/sync_all_pipelines"
    expect(response).to have_http_status(:unauthorized).or have_http_status(:forbidden)
  end
end
