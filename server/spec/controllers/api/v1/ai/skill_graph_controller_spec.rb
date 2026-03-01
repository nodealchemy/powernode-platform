# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::Ai::SkillGraphController, type: :controller do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: ["ai.skills.read", "ai.skills.update", "ai.knowledge_graph.manage", "ai.teams.manage"]) }

  before { sign_in_as_user(user) }

  describe "GET #subgraph" do
    it "returns skill subgraph" do
      allow_any_instance_of(Ai::SkillGraph::BridgeService).to receive(:skill_subgraph).and_return(
        nodes: [], edges: [], node_count: 0, edge_count: 0
      )

      get :subgraph
      expect(response).to have_http_status(:ok)
      expect(json_response["success"]).to be true
      expect(json_response["data"]["node_count"]).to eq(0)
    end
  end

  describe "POST #sync" do
    it "triggers full sync" do
      allow_any_instance_of(Ai::SkillGraph::BridgeService).to receive(:sync_all_skills).and_return(
        synced: 5, failed: 0
      )

      post :sync
      expect(response).to have_http_status(:ok)
      expect(json_response["data"]["synced"]).to eq(5)
    end

    it "requires ai.skills.update permission" do
      user_no_perms = create(:user, account: account, permissions: [])
      sign_in_as_user(user_no_perms)

      post :sync
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "POST #discover" do
    it "returns traversal results" do
      allow_any_instance_of(Ai::SkillGraph::TraversalService).to receive(:traverse).and_return(
        discovered_skills: [], paths: [], seed_count: 0, token_estimate: 0
      )

      post :discover, params: { task_context: "review my code" }
      expect(response).to have_http_status(:ok)
    end

    it "requires task_context" do
      post :discover
      expect(response).to have_http_status(:bad_request)
    end
  end

  describe "POST #create_edge" do
    let(:skill_a) { create(:ai_skill, account: account, name: "A", category: "productivity") }
    let(:skill_b) { create(:ai_skill, account: account, name: "B", category: "sales") }

    it "creates a skill edge" do
      edge = create(:ai_knowledge_graph_edge, account: account)
      allow_any_instance_of(Ai::SkillGraph::BridgeService).to receive(:create_skill_edge).and_return(edge)

      post :create_edge, params: {
        source_skill_id: skill_a.id,
        target_skill_id: skill_b.id,
        relation_type: "requires"
      }
      expect(response).to have_http_status(:ok)
      expect(json_response["data"]["edge"]).to be_present
    end

    it "returns error for invalid relation type" do
      allow_any_instance_of(Ai::SkillGraph::BridgeService).to receive(:create_skill_edge).and_raise(
        ArgumentError, "Invalid skill relation_type"
      )

      post :create_edge, params: {
        source_skill_id: skill_a.id,
        target_skill_id: skill_b.id,
        relation_type: "invalid"
      }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "PATCH #update_edge" do
    let!(:edge) { create(:ai_knowledge_graph_edge, account: account) }

    it "updates edge weight and confidence" do
      patch :update_edge, params: { id: edge.id, weight: 0.8, confidence: 0.9 }
      expect(response).to have_http_status(:ok)
      edge.reload
      expect(edge.weight).to eq(0.8)
      expect(edge.confidence).to eq(0.9)
    end

    it "returns not found for missing edge" do
      patch :update_edge, params: { id: SecureRandom.uuid, weight: 0.5 }
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE #destroy_edge" do
    let!(:edge) { create(:ai_knowledge_graph_edge, account: account) }

    it "deletes the edge" do
      allow_any_instance_of(Ai::SkillGraph::BridgeService).to receive(:remove_skill_edge)

      delete :destroy_edge, params: { id: edge.id }
      expect(response).to have_http_status(:ok)
      expect(json_response["data"]["deleted"]).to be true
    end
  end

  describe "POST #auto_detect" do
    let!(:skill) { create(:ai_skill, account: account, name: "Test Skill", category: "productivity") }

    it "returns suggestions" do
      allow_any_instance_of(Ai::SkillGraph::BridgeService).to receive(:auto_detect_relationships).and_return([])

      post :auto_detect, params: { skill_id: skill.id }
      expect(response).to have_http_status(:ok)
      expect(json_response["data"]["suggestions"]).to eq([])
    end

    it "returns not found for missing skill" do
      post :auto_detect, params: { skill_id: SecureRandom.uuid }
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET #team_coverage" do
    let!(:team) { create(:ai_agent_team, account: account) }

    it "returns coverage analysis" do
      allow_any_instance_of(Ai::SkillGraph::TeamCoverageService).to receive(:analyze_coverage).and_return(
        team_id: team.id, total_skills: 0, covered_skills: 0, coverage_ratio: 0.0,
        category_breakdown: [], connectivity_score: 0.0, uncovered_skills: [], agent_skill_map: {}
      )

      get :team_coverage, params: { team_id: team.id }
      expect(response).to have_http_status(:ok)
      expect(json_response["data"]["team_id"]).to eq(team.id)
    end

    it "returns not found for missing team" do
      get :team_coverage, params: { team_id: SecureRandom.uuid }
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST #compose_team" do
    it "returns team composition suggestion" do
      allow_any_instance_of(Ai::SkillGraph::TeamCoverageService).to receive(:compose_team_suggestion).and_return(
        members: [], total_needed: 0, total_covered: 0, uncovered_skill_ids: []
      )

      post :compose_team, params: { task_context: "build an API" }
      expect(response).to have_http_status(:ok)
    end

    it "requires task_context" do
      post :compose_team
      expect(response).to have_http_status(:bad_request)
    end
  end

  describe "GET #agent_context" do
    let!(:agent) { create(:ai_agent, account: account) }

    it "returns agent skill graph context" do
      allow_any_instance_of(Ai::SkillGraph::ContextEnrichmentService).to receive(:enrich).and_return(
        context_block: "", metadata: {}
      )

      get :agent_context, params: { agent_id: agent.id }
      expect(response).to have_http_status(:ok)
    end

    it "returns not found for missing agent" do
      get :agent_context, params: { agent_id: SecureRandom.uuid }
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "authentication" do
    it "returns 401 without token" do
      @request.env.delete("HTTP_AUTHORIZATION")
      get :subgraph
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
