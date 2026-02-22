# frozen_string_literal: true

require "rails_helper"

RSpec.describe "POST /api/v1/ai/skill_graph/conflict_check", type: :request do
  let(:account) { create(:account) }
  let(:manage_user) { create(:user, account: account, permissions: ["ai.knowledge_graph.manage"]) }
  let(:read_user) { create(:user, account: account, permissions: ["ai.skills.read"]) }
  let(:manage_headers) { auth_headers_for(manage_user) }
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

  let!(:skill) { create(:ai_skill, account: account) }

  before do
    allow_any_instance_of(Ai::Skill).to receive(:sync_to_knowledge_graph)
    allow_any_instance_of(Ai::Memory::EmbeddingService).to receive(:generate).and_return(Array.new(1536, 0.1))
    allow(WorkerJobService).to receive(:enqueue_ai_skill_conflict_check)
  end

  context "with worker authentication" do
    before do
      allow_any_instance_of(Ai::SkillGraph::ConflictDetectionService).to receive(:detect_duplicates).and_return([])
      allow_any_instance_of(Ai::SkillGraph::ConflictDetectionService).to receive(:detect_overlapping).and_return([])
    end

    it "checks conflicts for the skill" do
      post "/api/v1/ai/skill_graph/conflict_check",
           params: { skill_id: skill.id }.to_json,
           headers: worker_headers

      expect_success_response
      data = json_response_data
      expect(data["skill_id"]).to eq(skill.id)
      expect(data["conflicts_found"]).to eq(0)
      expect(data["duplicates"]).to eq(0)
      expect(data["overlapping"]).to eq(0)
    end

    it "returns not found for missing skill" do
      post "/api/v1/ai/skill_graph/conflict_check",
           params: { skill_id: SecureRandom.uuid }.to_json,
           headers: worker_headers

      expect_error_response("Skill not found", 404)
    end

    it "reports detected conflicts" do
      allow_any_instance_of(Ai::SkillGraph::ConflictDetectionService)
        .to receive(:detect_duplicates).and_return([{ id: "fake1" }])
      allow_any_instance_of(Ai::SkillGraph::ConflictDetectionService)
        .to receive(:detect_overlapping).and_return([{ id: "fake2" }, { id: "fake3" }])

      post "/api/v1/ai/skill_graph/conflict_check",
           params: { skill_id: skill.id }.to_json,
           headers: worker_headers

      expect_success_response
      data = json_response_data
      expect(data["conflicts_found"]).to eq(3)
      expect(data["duplicates"]).to eq(1)
      expect(data["overlapping"]).to eq(2)
    end
  end

  context "with user authentication (ai.knowledge_graph.manage)" do
    before do
      allow_any_instance_of(Ai::SkillGraph::ConflictDetectionService).to receive(:detect_duplicates).and_return([])
      allow_any_instance_of(Ai::SkillGraph::ConflictDetectionService).to receive(:detect_overlapping).and_return([])
    end

    it "runs conflict check" do
      post "/api/v1/ai/skill_graph/conflict_check",
           params: { skill_id: skill.id },
           headers: manage_headers,
           as: :json

      expect_success_response
    end
  end

  context "with insufficient permissions" do
    it "returns forbidden for read-only user" do
      post "/api/v1/ai/skill_graph/conflict_check",
           params: { skill_id: skill.id },
           headers: read_headers,
           as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end

  context "without authentication" do
    it "returns unauthorized" do
      post "/api/v1/ai/skill_graph/conflict_check",
           params: { skill_id: skill.id }.to_json,
           headers: { "Content-Type" => "application/json" }

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
