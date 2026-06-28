# frozen_string_literal: true

require "rails_helper"

# Bulk purge endpoint that collapses the AiMemoryPoolCleanupJob per-pool DELETE N+1 into one call.
RSpec.describe "Api::V1::Internal::Ai::MemoryPools#purge_expired", type: :request do
  let(:account)       { create(:account) }
  let(:system_worker) { create(:worker, :system_worker, account: account) }
  let(:worker_headers) do
    { "X-Forwarded-Tls-Client-Cert-Info" => CGI.escape(%(Subject="CN=#{system_worker.node_instance_id}")) }
  end

  def purge_expired
    post "/api/v1/internal/ai/memory_pools/purge_expired", headers: worker_headers, as: :json
    response
  end

  it "requires worker mTLS authentication" do
    post "/api/v1/internal/ai/memory_pools/purge_expired"
    expect(response).to have_http_status(:unauthorized)
  end

  context "with a mix of expired and active pools" do
    # data_size_bytes is recomputed from `data` on save, so vary `data` to get distinct sizes.
    let!(:expired_a) { create(:ai_memory_pool, :expired, account: account, data: { "a" => "x" * 200 }) }
    let!(:expired_b) { create(:ai_memory_pool, :expired, account: account, data: { "b" => "y" * 800 }) }
    let!(:active)    { create(:ai_memory_pool, account: account, expires_at: 1.day.from_now, data: { "c" => "z" * 50 }) }

    it "deletes every expired pool in a single request and keeps active ones" do
      expect { purge_expired }.to change { Ai::MemoryPool.count }.by(-2)
      expect(Ai::MemoryPool.exists?(expired_a.id)).to be(false)
      expect(Ai::MemoryPool.exists?(expired_b.id)).to be(false)
      expect(Ai::MemoryPool.exists?(active.id)).to be(true)
    end

    it "reports the count and total bytes freed" do
      expected_bytes = expired_a.data_size_bytes + expired_b.data_size_bytes
      expect(expected_bytes).to be > 0 # sanity: sizes are real
      body = JSON.parse(purge_expired.body)["data"]
      expect(body["pools_cleaned"]).to eq(2)
      expect(body["bytes_freed"]).to eq(expected_bytes)
    end
  end

  it "is a no-op (zeros) when nothing is expired" do
    create(:ai_memory_pool, account: account, expires_at: 1.day.from_now)
    body = JSON.parse(purge_expired.body)["data"]
    expect(body["pools_cleaned"]).to eq(0)
    expect(body["bytes_freed"]).to eq(0)
  end
end
