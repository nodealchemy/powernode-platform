# frozen_string_literal: true

require "rails_helper"

RSpec.describe "POST /api/v1/ai/memory/consolidate_entry", type: :request do
  let(:account) { create(:account) }
  let(:write_user) { create(:user, account: account, permissions: ["ai.memory.read", "ai.memory.write"]) }
  let(:read_user) { create(:user, account: account, permissions: ["ai.memory.read"]) }
  let(:write_headers) { auth_headers_for(write_user) }
  let(:read_headers) { auth_headers_for(read_user) }

  # Worker auth: JWT token for a real Worker record (sets current_worker + current_account)
  let(:worker) { create(:worker, account: account) }
  let(:worker_headers) do
    payload = {
      sub: worker.id,
      account_id: worker.account_id,
      type: "worker",
      permissions: worker.permission_names,
      version: Security::JwtService::CURRENT_TOKEN_VERSION
    }
    token = Security::JwtService.encode(payload)
    { "Authorization" => "Bearer #{token}", "Content-Type" => "application/json" }
  end

  let(:agent) { create(:ai_agent, account: account) }
  let!(:entry) do
    create(:ai_agent_short_term_memory,
      account: account,
      agent: agent,
      access_count: 5
    )
  end

  before do
    allow(WorkerJobService).to receive(:enqueue_ai_consolidate_memory_entry)
    allow(WorkerJobService).to receive(:enqueue_ai_skill_conflict_check)
  end

  context "with worker authentication" do
    before do
      allow_any_instance_of(Ai::Memory::RouterService).to receive(:consolidate!)
        .and_return({ promoted: 1, skipped_duplicates: 0 })
    end

    it "consolidates the STM entry to long-term" do
      post "/api/v1/ai/memory/consolidate_entry",
           params: { entry_id: entry.id }.to_json,
           headers: worker_headers

      expect_success_response
    end

    it "returns not found for missing entry" do
      post "/api/v1/ai/memory/consolidate_entry",
           params: { entry_id: SecureRandom.uuid }.to_json,
           headers: worker_headers

      expect_error_response("Entry not found", 404)
    end

    it "skips expired entries" do
      expired = create(:ai_agent_short_term_memory, :expired, account: account, agent: agent)

      post "/api/v1/ai/memory/consolidate_entry",
           params: { entry_id: expired.id }.to_json,
           headers: worker_headers

      expect_success_response
      data = json_response_data
      expect(data["consolidated"]).to be false
      expect(data["reason"]).to eq("expired")
    end
  end

  context "with user authentication (ai.memory.write)" do
    before do
      allow_any_instance_of(Ai::Memory::RouterService).to receive(:consolidate!)
        .and_return({ promoted: 1, skipped_duplicates: 0 })
    end

    it "consolidates the entry" do
      post "/api/v1/ai/memory/consolidate_entry",
           params: { entry_id: entry.id },
           headers: write_headers,
           as: :json

      expect_success_response
    end
  end

  context "with insufficient permissions" do
    it "returns forbidden for read-only user" do
      post "/api/v1/ai/memory/consolidate_entry",
           params: { entry_id: entry.id },
           headers: read_headers,
           as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end

  context "without authentication" do
    it "returns unauthorized" do
      post "/api/v1/ai/memory/consolidate_entry",
           params: { entry_id: entry.id }.to_json,
           headers: { "Content-Type" => "application/json" }

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
