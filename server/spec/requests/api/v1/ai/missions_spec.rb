# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Ai::Missions", type: :request do
  let(:user) { user_with_permissions("ai.missions.read", "ai.missions.manage") }
  let(:account) { user.account }
  let(:headers) { auth_headers_for(user) }

  describe "GET /api/v1/ai/missions" do
    let!(:mission) { create(:ai_mission, account: account, created_by: user) }

    it "returns missions for the account" do
      get "/api/v1/ai/missions", headers: headers, as: :json
      expect_success_response
      expect(json_response_data["missions"]).to be_an(Array)
      expect(json_response_data["missions"].length).to eq(1)
    end

    it "filters by status" do
      create(:ai_mission, :active, account: account, created_by: user)
      get "/api/v1/ai/missions?status=active", headers: headers, as: :json
      expect_success_response
      missions = json_response_data["missions"]
      expect(missions.all? { |m| m["status"] == "active" }).to be true
    end

    include_examples "requires authentication", :get, "/api/v1/ai/missions"
  end

  describe "POST /api/v1/ai/missions" do
    let(:repository) { create(:git_repository, account: account) }

    it "creates a new mission" do
      post "/api/v1/ai/missions", headers: headers, params: {
        name: "Test Mission",
        mission_type: "development",
        objective: "Build a feature",
        repository_id: repository.id
      }, as: :json
      expect_success_response
      expect(json_response_data["mission"]["name"]).to eq("Test Mission")
    end

    it "validates required fields" do
      post "/api/v1/ai/missions", headers: headers, params: { name: "" }, as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "GET /api/v1/ai/missions/:id" do
    let(:mission) { create(:ai_mission, account: account, created_by: user) }

    it "returns mission details" do
      get "/api/v1/ai/missions/#{mission.id}", headers: headers, as: :json
      expect_success_response
      expect(json_response_data["mission"]["id"]).to eq(mission.id)
    end

    it "returns 404 for unknown mission" do
      get "/api/v1/ai/missions/nonexistent-id", headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/ai/missions/:id/start" do
    let(:mission) { create(:ai_mission, account: account, created_by: user) }

    it "starts the mission" do
      post "/api/v1/ai/missions/#{mission.id}/start", headers: headers, as: :json
      expect_success_response
      expect(json_response_data["mission"]["status"]).to eq("active")
    end
  end

  describe "POST /api/v1/ai/missions/:id/cancel" do
    let(:mission) { create(:ai_mission, :active, account: account, created_by: user) }

    it "cancels the mission" do
      post "/api/v1/ai/missions/#{mission.id}/cancel", headers: headers, params: { reason: "Changed plans" }, as: :json
      expect_success_response
      expect(json_response_data["mission"]["status"]).to eq("cancelled")
    end
  end

  describe "POST /api/v1/ai/missions/:id/pause" do
    let(:mission) { create(:ai_mission, :active, account: account, created_by: user) }

    it "pauses the mission" do
      post "/api/v1/ai/missions/#{mission.id}/pause", headers: headers, as: :json
      expect_success_response
      expect(json_response_data["mission"]["status"]).to eq("paused")
    end
  end

  describe "DELETE /api/v1/ai/missions/:id" do
    let(:mission) { create(:ai_mission, :completed, account: account, created_by: user) }

    it "deletes a terminal mission" do
      delete "/api/v1/ai/missions/#{mission.id}", headers: headers, as: :json
      expect_success_response
    end

    it "refuses to delete active missions" do
      active_mission = create(:ai_mission, :active, account: account, created_by: user)
      delete "/api/v1/ai/missions/#{active_mission.id}", headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end
  end
end
