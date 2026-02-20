# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Ai::SkillGraph Lifecycle Endpoints", type: :request do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }

  # Stub sync_to_knowledge_graph globally to avoid side effects
  before do
    allow_any_instance_of(Ai::Skill).to receive(:sync_to_knowledge_graph)
    allow_any_instance_of(Ai::Agent).to receive(:sync_to_knowledge_graph)
    allow_any_instance_of(Ai::Memory::EmbeddingService).to receive(:generate).and_return(Array.new(1536, 0.1))
  end

  # ===================================================================
  # 1. Research
  # ===================================================================
  describe "POST /api/v1/ai/skill_graph/research" do
    let(:path) { "/api/v1/ai/skill_graph/research" }
    let(:user) { user_with_permissions("ai.skills.create", account: account) }
    let(:headers) { auth_headers_for(user) }

    let(:research_result) do
      {
        topic: "data analysis",
        sources_queried: %w[knowledge_graph knowledge_bases mcp],
        findings: { knowledge_graph: [], knowledge_bases: [] },
        total_findings: 0,
        researched_at: Time.current
      }
    end

    before do
      allow_any_instance_of(Ai::SkillGraph::ResearchService)
        .to receive(:research).and_return(research_result)
    end

    it "returns research results for a valid topic" do
      post path, params: { topic: "data analysis", sources: %w[knowledge_graph knowledge_bases] }.to_json, headers: headers

      expect_success_response
      data = json_response_data
      expect(data["topic"]).to eq("data analysis")
    end

    it "accepts optional sources parameter" do
      post path, params: { topic: "data analysis", sources: %w[knowledge_graph] }.to_json, headers: headers

      expect_success_response
    end

    it "returns 400 when topic is missing" do
      post path, params: {}.to_json, headers: headers

      expect_error_response("topic required", :bad_request)
    end

    it "returns 401 without authentication" do
      post path, params: { topic: "test" }.to_json,
           headers: { "Content-Type" => "application/json" }

      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 403 without ai.skills.create permission" do
      user_no_perm = user_with_permissions(account: account)
      post path, params: { topic: "test" }.to_json,
           headers: auth_headers_for(user_no_perm)

      expect(response).to have_http_status(:forbidden)
    end
  end

  # ===================================================================
  # 2. Proposals CRUD
  # ===================================================================
  describe "Proposals" do
    describe "GET /api/v1/ai/skill_graph/proposals" do
      let(:path) { "/api/v1/ai/skill_graph/proposals" }
      let(:user) { user_with_permissions("ai.skills.read", account: account) }
      let(:headers) { auth_headers_for(user) }

      let!(:proposal1) { create(:ai_skill_proposal, account: account, status: "draft") }
      let!(:proposal2) { create(:ai_skill_proposal, :proposed, account: account) }
      let!(:other_proposal) { create(:ai_skill_proposal, account: other_account) }

      it "returns proposals for the current account" do
        get path, headers: headers

        expect_success_response
        data = json_response_data
        expect(data["proposals"].size).to eq(2)
        proposal_ids = data["proposals"].map { |p| p["id"] }
        expect(proposal_ids).to include(proposal1.id, proposal2.id)
        expect(proposal_ids).not_to include(other_proposal.id)
      end

      it "filters by status" do
        get path, params: { status: "proposed" }, headers: headers

        expect_success_response
        data = json_response_data
        expect(data["proposals"].size).to eq(1)
        expect(data["proposals"].first["status"]).to eq("proposed")
      end

      it "returns 401 without authentication" do
        get path, headers: { "Content-Type" => "application/json" }

        expect(response).to have_http_status(:unauthorized)
      end

      it "returns 403 without ai.skills.read permission" do
        user_no_perm = user_with_permissions(account: account)
        get path, headers: auth_headers_for(user_no_perm)

        expect(response).to have_http_status(:forbidden)
      end

      it "does not return proposals from other accounts" do
        get path, headers: headers

        data = json_response_data
        proposal_ids = data["proposals"].map { |p| p["id"] }
        expect(proposal_ids).not_to include(other_proposal.id)
      end
    end

    describe "POST /api/v1/ai/skill_graph/proposals" do
      let(:path) { "/api/v1/ai/skill_graph/proposals" }
      let(:user) { user_with_permissions("ai.skills.create", account: account) }
      let(:headers) { auth_headers_for(user) }

      let(:valid_params) do
        {
          name: "New Analysis Skill",
          description: "Analyzes data patterns",
          category: "productivity",
          system_prompt: "You are an analysis assistant."
        }
      end

      it "creates a proposal" do
        expect {
          post path, params: valid_params.to_json, headers: headers
        }.to change(Ai::SkillProposal, :count).by(1)

        expect_success_response
        data = json_response_data
        expect(data["proposal"]["name"]).to eq("New Analysis Skill")
        expect(data["proposal"]["status"]).to eq("draft")
      end

      it "associates proposal with current account and user" do
        post path, params: valid_params.to_json, headers: headers

        proposal = Ai::SkillProposal.last
        expect(proposal.account_id).to eq(account.id)
        expect(proposal.proposed_by_user_id).to eq(user.id)
      end

      it "returns 422 for invalid params (missing name)" do
        post path, params: { description: "no name" }.to_json, headers: headers

        expect(response).to have_http_status(:unprocessable_content)
      end

      it "returns 401 without authentication" do
        post path, params: valid_params.to_json,
             headers: { "Content-Type" => "application/json" }

        expect(response).to have_http_status(:unauthorized)
      end

      it "returns 403 without ai.skills.create permission" do
        user_no_perm = user_with_permissions(account: account)
        post path, params: valid_params.to_json,
             headers: auth_headers_for(user_no_perm)

        expect(response).to have_http_status(:forbidden)
      end
    end

    describe "GET /api/v1/ai/skill_graph/proposals/:id" do
      let(:user) { user_with_permissions("ai.skills.read", account: account) }
      let(:headers) { auth_headers_for(user) }
      let(:proposal) { create(:ai_skill_proposal, account: account) }
      let(:other_proposal) { create(:ai_skill_proposal, account: other_account) }

      it "returns proposal details" do
        get "/api/v1/ai/skill_graph/proposals/#{proposal.id}", headers: headers

        expect_success_response
        data = json_response_data
        expect(data["proposal"]["id"]).to eq(proposal.id)
        expect(data["proposal"]["name"]).to eq(proposal.name)
      end

      it "returns 404 for non-existent proposal" do
        get "/api/v1/ai/skill_graph/proposals/#{SecureRandom.uuid}", headers: headers

        expect(response).to have_http_status(:not_found)
      end

      it "returns 404 for another account's proposal" do
        get "/api/v1/ai/skill_graph/proposals/#{other_proposal.id}", headers: headers

        expect(response).to have_http_status(:not_found)
      end

      it "returns 401 without authentication" do
        get "/api/v1/ai/skill_graph/proposals/#{proposal.id}",
            headers: { "Content-Type" => "application/json" }

        expect(response).to have_http_status(:unauthorized)
      end

      it "returns 403 without ai.skills.read permission" do
        user_no_perm = user_with_permissions(account: account)
        get "/api/v1/ai/skill_graph/proposals/#{proposal.id}",
            headers: auth_headers_for(user_no_perm)

        expect(response).to have_http_status(:forbidden)
      end
    end

    describe "POST /api/v1/ai/skill_graph/proposals/:id/submit" do
      let(:user) { user_with_permissions("ai.skills.create", account: account) }
      let(:headers) { auth_headers_for(user) }
      let(:proposal) { create(:ai_skill_proposal, account: account, status: "draft") }

      before do
        allow_any_instance_of(Ai::SkillGraph::LifecycleService)
          .to receive(:submit_proposal).and_call_original
      end

      it "submits a draft proposal" do
        post "/api/v1/ai/skill_graph/proposals/#{proposal.id}/submit", headers: headers

        expect_success_response
        data = json_response_data
        expect(data["proposal"]["status"]).to eq("proposed")
      end

      it "returns 404 for non-existent proposal" do
        post "/api/v1/ai/skill_graph/proposals/#{SecureRandom.uuid}/submit", headers: headers

        expect(response).to have_http_status(:not_found)
      end

      it "returns 422 when submitting a non-draft proposal" do
        proposed = create(:ai_skill_proposal, :proposed, account: account)
        post "/api/v1/ai/skill_graph/proposals/#{proposed.id}/submit", headers: headers

        expect(response).to have_http_status(:unprocessable_content)
      end

      it "returns 401 without authentication" do
        post "/api/v1/ai/skill_graph/proposals/#{proposal.id}/submit",
             headers: { "Content-Type" => "application/json" }

        expect(response).to have_http_status(:unauthorized)
      end

      it "returns 403 without ai.skills.create permission" do
        user_no_perm = user_with_permissions(account: account)
        post "/api/v1/ai/skill_graph/proposals/#{proposal.id}/submit",
             headers: auth_headers_for(user_no_perm)

        expect(response).to have_http_status(:forbidden)
      end
    end

    describe "POST /api/v1/ai/skill_graph/proposals/:id/approve" do
      let(:user) { user_with_permissions("ai.skills.update", account: account) }
      let(:headers) { auth_headers_for(user) }
      let(:proposal) { create(:ai_skill_proposal, :proposed, account: account) }

      it "approves a proposed proposal" do
        allow_any_instance_of(Ai::SkillGraph::LifecycleService)
          .to receive(:approve_proposal).and_return(proposal.tap { |p| p.status = "approved" })

        post "/api/v1/ai/skill_graph/proposals/#{proposal.id}/approve", headers: headers

        expect_success_response
      end

      it "returns 404 for non-existent proposal" do
        post "/api/v1/ai/skill_graph/proposals/#{SecureRandom.uuid}/approve", headers: headers

        expect(response).to have_http_status(:not_found)
      end

      it "returns 401 without authentication" do
        post "/api/v1/ai/skill_graph/proposals/#{proposal.id}/approve",
             headers: { "Content-Type" => "application/json" }

        expect(response).to have_http_status(:unauthorized)
      end

      it "returns 403 without ai.skills.update permission" do
        user_no_perm = user_with_permissions(account: account)
        post "/api/v1/ai/skill_graph/proposals/#{proposal.id}/approve",
             headers: auth_headers_for(user_no_perm)

        expect(response).to have_http_status(:forbidden)
      end
    end

    describe "POST /api/v1/ai/skill_graph/proposals/:id/reject" do
      let(:user) { user_with_permissions("ai.skills.update", account: account) }
      let(:headers) { auth_headers_for(user) }
      let(:proposal) { create(:ai_skill_proposal, :proposed, account: account) }

      it "rejects a proposed proposal with a reason" do
        allow_any_instance_of(Ai::SkillGraph::LifecycleService)
          .to receive(:reject_proposal).and_return(proposal.tap { |p| p.status = "rejected" })

        post "/api/v1/ai/skill_graph/proposals/#{proposal.id}/reject",
             params: { reason: "Duplicates existing skill" }.to_json,
             headers: headers

        expect_success_response
      end

      it "uses default reason when none provided" do
        allow_any_instance_of(Ai::SkillGraph::LifecycleService)
          .to receive(:reject_proposal).and_return(proposal.tap { |p| p.status = "rejected" })

        post "/api/v1/ai/skill_graph/proposals/#{proposal.id}/reject",
             params: {}.to_json, headers: headers

        expect_success_response
      end

      it "returns 404 for non-existent proposal" do
        post "/api/v1/ai/skill_graph/proposals/#{SecureRandom.uuid}/reject",
             params: { reason: "test" }.to_json, headers: headers

        expect(response).to have_http_status(:not_found)
      end

      it "returns 401 without authentication" do
        post "/api/v1/ai/skill_graph/proposals/#{proposal.id}/reject",
             params: { reason: "test" }.to_json,
             headers: { "Content-Type" => "application/json" }

        expect(response).to have_http_status(:unauthorized)
      end

      it "returns 403 without ai.skills.update permission" do
        user_no_perm = user_with_permissions(account: account)
        post "/api/v1/ai/skill_graph/proposals/#{proposal.id}/reject",
             params: { reason: "test" }.to_json,
             headers: auth_headers_for(user_no_perm)

        expect(response).to have_http_status(:forbidden)
      end
    end

    describe "POST /api/v1/ai/skill_graph/proposals/:id/create_skill" do
      let(:user) { user_with_permissions("ai.skills.create", account: account) }
      let(:headers) { auth_headers_for(user) }
      let(:proposal) { create(:ai_skill_proposal, :approved, account: account) }
      let(:skill) { create(:ai_skill, account: account) }

      let(:create_result) do
        { skill: skill, proposal: proposal.tap { |p| p.status = "created" } }
      end

      before do
        allow_any_instance_of(Ai::SkillGraph::LifecycleService)
          .to receive(:create_skill_from_proposal).and_return(create_result)
      end

      it "creates a skill from an approved proposal" do
        post "/api/v1/ai/skill_graph/proposals/#{proposal.id}/create_skill", headers: headers

        expect_success_response
        data = json_response_data
        expect(data).to have_key("skill")
        expect(data).to have_key("proposal")
      end

      it "returns 404 for non-existent proposal" do
        allow_any_instance_of(Ai::SkillGraph::LifecycleService)
          .to receive(:create_skill_from_proposal)
          .and_raise(ActiveRecord::RecordNotFound)

        post "/api/v1/ai/skill_graph/proposals/#{SecureRandom.uuid}/create_skill", headers: headers

        expect(response).to have_http_status(:not_found)
      end

      it "returns 401 without authentication" do
        post "/api/v1/ai/skill_graph/proposals/#{proposal.id}/create_skill",
             headers: { "Content-Type" => "application/json" }

        expect(response).to have_http_status(:unauthorized)
      end

      it "returns 403 without ai.skills.create permission" do
        user_no_perm = user_with_permissions(account: account)
        post "/api/v1/ai/skill_graph/proposals/#{proposal.id}/create_skill",
             headers: auth_headers_for(user_no_perm)

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  # ===================================================================
  # 3. Conflicts & Health
  # ===================================================================
  describe "Conflicts & Health" do
    describe "GET /api/v1/ai/skill_graph/conflicts" do
      let(:path) { "/api/v1/ai/skill_graph/conflicts" }
      let(:user) { user_with_permissions("ai.skills.read", account: account) }
      let(:headers) { auth_headers_for(user) }

      let!(:conflict1) { create(:ai_skill_conflict, account: account) }
      let!(:conflict2) { create(:ai_skill_conflict, :overlapping, account: account) }
      let!(:other_conflict) { create(:ai_skill_conflict, account: other_account) }

      it "returns conflicts for the current account" do
        get path, headers: headers

        expect_success_response
        data = json_response_data
        expect(data["conflicts"].size).to eq(2)
        conflict_ids = data["conflicts"].map { |c| c["id"] }
        expect(conflict_ids).to include(conflict1.id, conflict2.id)
        expect(conflict_ids).not_to include(other_conflict.id)
      end

      it "filters by status" do
        resolved = create(:ai_skill_conflict, :resolved, account: account)
        get path, params: { status: "resolved" }, headers: headers

        expect_success_response
        data = json_response_data
        conflict_ids = data["conflicts"].map { |c| c["id"] }
        expect(conflict_ids).to include(resolved.id)
        expect(conflict_ids).not_to include(conflict1.id)
      end

      it "filters by conflict type" do
        get path, params: { type: "overlapping" }, headers: headers

        expect_success_response
        data = json_response_data
        data["conflicts"].each do |c|
          expect(c["conflict_type"]).to eq("overlapping")
        end
      end

      it "returns 401 without authentication" do
        get path, headers: { "Content-Type" => "application/json" }

        expect(response).to have_http_status(:unauthorized)
      end

      it "returns 403 without ai.skills.read permission" do
        user_no_perm = user_with_permissions(account: account)
        get path, headers: auth_headers_for(user_no_perm)

        expect(response).to have_http_status(:forbidden)
      end

      it "does not return conflicts from other accounts" do
        get path, headers: headers

        data = json_response_data
        conflict_ids = data["conflicts"].map { |c| c["id"] }
        expect(conflict_ids).not_to include(other_conflict.id)
      end
    end

    describe "POST /api/v1/ai/skill_graph/conflicts/:id/resolve" do
      let(:user) { user_with_permissions("ai.knowledge_graph.manage", account: account) }
      let(:headers) { auth_headers_for(user) }
      let(:conflict) { create(:ai_skill_conflict, account: account) }

      before do
        allow_any_instance_of(Ai::SkillGraph::AutoRepairService)
          .to receive(:resolve_conflict).and_return({ success: true })
      end

      it "resolves a conflict" do
        post "/api/v1/ai/skill_graph/conflicts/#{conflict.id}/resolve", headers: headers

        expect_success_response
        data = json_response_data
        expect(data["conflict"]).to have_key("id")
      end

      it "returns 404 for non-existent conflict" do
        post "/api/v1/ai/skill_graph/conflicts/#{SecureRandom.uuid}/resolve", headers: headers

        expect(response).to have_http_status(:not_found)
      end

      it "returns 404 for another account's conflict" do
        other_conflict = create(:ai_skill_conflict, account: other_account)
        post "/api/v1/ai/skill_graph/conflicts/#{other_conflict.id}/resolve", headers: headers

        expect(response).to have_http_status(:not_found)
      end

      it "returns 401 without authentication" do
        post "/api/v1/ai/skill_graph/conflicts/#{conflict.id}/resolve",
             headers: { "Content-Type" => "application/json" }

        expect(response).to have_http_status(:unauthorized)
      end

      it "returns 403 without ai.knowledge_graph.manage permission" do
        user_no_perm = user_with_permissions(account: account)
        post "/api/v1/ai/skill_graph/conflicts/#{conflict.id}/resolve",
             headers: auth_headers_for(user_no_perm)

        expect(response).to have_http_status(:forbidden)
      end
    end

    describe "POST /api/v1/ai/skill_graph/conflicts/:id/dismiss" do
      let(:user) { user_with_permissions("ai.knowledge_graph.manage", account: account) }
      let(:headers) { auth_headers_for(user) }
      let(:conflict) { create(:ai_skill_conflict, account: account) }

      it "dismisses a conflict" do
        post "/api/v1/ai/skill_graph/conflicts/#{conflict.id}/dismiss", headers: headers

        expect_success_response
        data = json_response_data
        expect(data["conflict"]["status"]).to eq("dismissed")
      end

      it "returns 404 for non-existent conflict" do
        post "/api/v1/ai/skill_graph/conflicts/#{SecureRandom.uuid}/dismiss", headers: headers

        expect(response).to have_http_status(:not_found)
      end

      it "returns 404 for another account's conflict" do
        other_conflict = create(:ai_skill_conflict, account: other_account)
        post "/api/v1/ai/skill_graph/conflicts/#{other_conflict.id}/dismiss", headers: headers

        expect(response).to have_http_status(:not_found)
      end

      it "returns 401 without authentication" do
        post "/api/v1/ai/skill_graph/conflicts/#{conflict.id}/dismiss",
             headers: { "Content-Type" => "application/json" }

        expect(response).to have_http_status(:unauthorized)
      end

      it "returns 403 without ai.knowledge_graph.manage permission" do
        user_no_perm = user_with_permissions(account: account)
        post "/api/v1/ai/skill_graph/conflicts/#{conflict.id}/dismiss",
             headers: auth_headers_for(user_no_perm)

        expect(response).to have_http_status(:forbidden)
      end
    end

    describe "POST /api/v1/ai/skill_graph/scan" do
      let(:path) { "/api/v1/ai/skill_graph/scan" }
      let(:user) { user_with_permissions("ai.knowledge_graph.manage", account: account) }
      let(:headers) { auth_headers_for(user) }

      let(:scan_result) do
        {
          conflicts: { duplicate: [], overlapping: [], stale: [] },
          summary: { duplicate: 0, overlapping: 0, stale: 0 },
          total: 0,
          scanned_at: Time.current
        }
      end

      before do
        allow_any_instance_of(Ai::SkillGraph::ConflictDetectionService)
          .to receive(:scan_all).and_return(scan_result)
      end

      it "runs a conflict scan" do
        post path, headers: headers

        expect_success_response
        data = json_response_data
        expect(data).to have_key("total")
        expect(data).to have_key("summary")
      end

      it "returns 401 without authentication" do
        post path, headers: { "Content-Type" => "application/json" }

        expect(response).to have_http_status(:unauthorized)
      end

      it "returns 403 without ai.knowledge_graph.manage permission" do
        user_no_perm = user_with_permissions(account: account)
        post path, headers: auth_headers_for(user_no_perm)

        expect(response).to have_http_status(:forbidden)
      end
    end

    describe "GET /api/v1/ai/skill_graph/health" do
      let(:path) { "/api/v1/ai/skill_graph/health" }
      let(:user) { user_with_permissions("ai.skills.read", account: account) }
      let(:headers) { auth_headers_for(user) }

      let(:health_result) do
        {
          health: {
            overall: 0.85,
            coverage: 0.9,
            connectivity: 0.8,
            freshness: 0.85,
            conflict_ratio: 0.05
          },
          kg_stats: { node_count: 10, edge_count: 15 },
          conflict_summary: { total: 2, critical: 0 },
          top_skills: [],
          bottom_skills: [],
          stale_skills: [],
          orphan_skills: []
        }
      end

      before do
        allow_any_instance_of(Ai::SkillGraph::HealthScoreService)
          .to receive(:comprehensive_report).and_return(health_result)
      end

      it "returns comprehensive health report" do
        get path, headers: headers

        expect_success_response
        data = json_response_data
        expect(data).to have_key("health")
      end

      it "returns 401 without authentication" do
        get path, headers: { "Content-Type" => "application/json" }

        expect(response).to have_http_status(:unauthorized)
      end

      it "returns 403 without ai.skills.read permission" do
        user_no_perm = user_with_permissions(account: account)
        get path, headers: auth_headers_for(user_no_perm)

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  # ===================================================================
  # 4. Evolution
  # ===================================================================
  describe "Evolution" do
    let(:skill) { create(:ai_skill, account: account) }

    describe "GET /api/v1/ai/skill_graph/skills/:skill_id/metrics" do
      let(:user) { user_with_permissions("ai.skills.read", account: account) }
      let(:headers) { auth_headers_for(user) }

      let(:metrics_result) do
        {
          skill_id: skill.id,
          name: skill.name,
          effectiveness_score: 0.75,
          usage_success_rate: 0.8,
          total_usage: 50,
          positive_count: 40,
          negative_count: 10,
          version_count: 2,
          active_conflicts_count: 0,
          last_used_at: Time.current,
          trend: "stable"
        }
      end

      before do
        allow_any_instance_of(Ai::SkillGraph::EvolutionService)
          .to receive(:skill_metrics).and_return(metrics_result)
      end

      it "returns skill metrics" do
        get "/api/v1/ai/skill_graph/skills/#{skill.id}/metrics", headers: headers

        expect_success_response
        data = json_response_data
        expect(data["skill_id"]).to eq(skill.id)
        expect(data["trend"]).to eq("stable")
      end

      it "returns not found for non-existent skill" do
        allow_any_instance_of(Ai::SkillGraph::EvolutionService)
          .to receive(:skill_metrics).and_raise(ActiveRecord::RecordNotFound)

        get "/api/v1/ai/skill_graph/skills/#{SecureRandom.uuid}/metrics", headers: headers

        expect(response).to have_http_status(:not_found)
      end

      it "returns 401 without authentication" do
        get "/api/v1/ai/skill_graph/skills/#{skill.id}/metrics",
            headers: { "Content-Type" => "application/json" }

        expect(response).to have_http_status(:unauthorized)
      end

      it "returns 403 without ai.skills.read permission" do
        user_no_perm = user_with_permissions(account: account)
        get "/api/v1/ai/skill_graph/skills/#{skill.id}/metrics",
            headers: auth_headers_for(user_no_perm)

        expect(response).to have_http_status(:forbidden)
      end
    end

    describe "GET /api/v1/ai/skill_graph/skills/:skill_id/versions" do
      let(:user) { user_with_permissions("ai.skills.read", account: account) }
      let(:headers) { auth_headers_for(user) }

      let!(:version1) { create(:ai_skill_version, ai_skill: skill, account: account, version: "1.0.0") }
      let!(:version2) { create(:ai_skill_version, :evolved, ai_skill: skill, account: account, version: "2.0.0") }

      let(:version_result) do
        [version2.version_summary, version1.version_summary]
      end

      before do
        allow_any_instance_of(Ai::SkillGraph::EvolutionService)
          .to receive(:version_history).and_return(version_result)
      end

      it "returns version history for a skill" do
        get "/api/v1/ai/skill_graph/skills/#{skill.id}/versions", headers: headers

        expect_success_response
        data = json_response_data
        expect(data["versions"].size).to eq(2)
      end

      it "returns not found for non-existent skill" do
        allow_any_instance_of(Ai::SkillGraph::EvolutionService)
          .to receive(:version_history).and_raise(ActiveRecord::RecordNotFound)

        get "/api/v1/ai/skill_graph/skills/#{SecureRandom.uuid}/versions", headers: headers

        expect(response).to have_http_status(:not_found)
      end

      it "returns 401 without authentication" do
        get "/api/v1/ai/skill_graph/skills/#{skill.id}/versions",
            headers: { "Content-Type" => "application/json" }

        expect(response).to have_http_status(:unauthorized)
      end

      it "returns 403 without ai.skills.read permission" do
        user_no_perm = user_with_permissions(account: account)
        get "/api/v1/ai/skill_graph/skills/#{skill.id}/versions",
            headers: auth_headers_for(user_no_perm)

        expect(response).to have_http_status(:forbidden)
      end
    end

    describe "POST /api/v1/ai/skill_graph/skills/:skill_id/evolve" do
      let(:user) { user_with_permissions("ai.skills.update", account: account) }
      let(:headers) { auth_headers_for(user) }

      let(:new_version) { create(:ai_skill_version, :evolved, ai_skill: skill, account: account) }

      before do
        allow_any_instance_of(Ai::SkillGraph::EvolutionService)
          .to receive(:propose_evolution).and_return(new_version)
      end

      it "proposes an evolution for a skill" do
        post "/api/v1/ai/skill_graph/skills/#{skill.id}/evolve", headers: headers

        expect_success_response
        data = json_response_data
        expect(data["version"]).to have_key("id")
        expect(data["version"]["change_type"]).to eq("evolution")
      end

      it "returns 422 when evolution fails" do
        allow_any_instance_of(Ai::SkillGraph::EvolutionService)
          .to receive(:propose_evolution).and_raise(StandardError, "Evolution failed")

        post "/api/v1/ai/skill_graph/skills/#{skill.id}/evolve", headers: headers

        expect(response).to have_http_status(:unprocessable_content)
      end

      it "returns 401 without authentication" do
        post "/api/v1/ai/skill_graph/skills/#{skill.id}/evolve",
             headers: { "Content-Type" => "application/json" }

        expect(response).to have_http_status(:unauthorized)
      end

      it "returns 403 without ai.skills.update permission" do
        user_no_perm = user_with_permissions(account: account)
        post "/api/v1/ai/skill_graph/skills/#{skill.id}/evolve",
             headers: auth_headers_for(user_no_perm)

        expect(response).to have_http_status(:forbidden)
      end
    end

    describe "POST /api/v1/ai/skill_graph/versions/:id/activate" do
      let(:user) { user_with_permissions("ai.skills.update", account: account) }
      let(:headers) { auth_headers_for(user) }
      let(:version) { create(:ai_skill_version, :inactive, ai_skill: skill, account: account) }

      before do
        allow_any_instance_of(Ai::SkillGraph::EvolutionService)
          .to receive(:activate_version).and_return(version)
      end

      it "activates a version" do
        post "/api/v1/ai/skill_graph/versions/#{version.id}/activate", headers: headers

        expect_success_response
        data = json_response_data
        expect(data["activated"]).to be true
      end

      it "returns 422 when activation fails" do
        allow_any_instance_of(Ai::SkillGraph::EvolutionService)
          .to receive(:activate_version).and_raise(StandardError, "Version not found")

        post "/api/v1/ai/skill_graph/versions/#{SecureRandom.uuid}/activate", headers: headers

        expect(response).to have_http_status(:unprocessable_content)
      end

      it "returns 401 without authentication" do
        post "/api/v1/ai/skill_graph/versions/#{version.id}/activate",
             headers: { "Content-Type" => "application/json" }

        expect(response).to have_http_status(:unauthorized)
      end

      it "returns 403 without ai.skills.update permission" do
        user_no_perm = user_with_permissions(account: account)
        post "/api/v1/ai/skill_graph/versions/#{version.id}/activate",
             headers: auth_headers_for(user_no_perm)

        expect(response).to have_http_status(:forbidden)
      end
    end

    describe "POST /api/v1/ai/skill_graph/record_outcome" do
      let(:path) { "/api/v1/ai/skill_graph/record_outcome" }
      let(:user) { user_with_permissions("ai.skills.update", account: account) }
      let(:headers) { auth_headers_for(user) }

      before do
        allow_any_instance_of(Ai::SkillGraph::EvolutionService)
          .to receive(:record_outcome).and_return({ skill_id: skill.id, outcome: "success" })
      end

      it "records a successful outcome" do
        post path, params: { skill_id: skill.id, successful: true }.to_json, headers: headers

        expect_success_response
        data = json_response_data
        expect(data["recorded"]).to be true
      end

      it "records a failure outcome" do
        allow_any_instance_of(Ai::SkillGraph::EvolutionService)
          .to receive(:record_outcome).and_return({ skill_id: skill.id, outcome: "failure" })

        post path, params: { skill_id: skill.id, successful: false }.to_json, headers: headers

        expect_success_response
        data = json_response_data
        expect(data["recorded"]).to be true
      end

      it "returns 422 when recording fails" do
        allow_any_instance_of(Ai::SkillGraph::EvolutionService)
          .to receive(:record_outcome).and_raise(StandardError, "Skill not found")

        post path, params: { skill_id: SecureRandom.uuid, successful: true }.to_json, headers: headers

        expect(response).to have_http_status(:unprocessable_content)
      end

      it "returns 401 without authentication" do
        post path, params: { skill_id: skill.id, successful: true }.to_json,
             headers: { "Content-Type" => "application/json" }

        expect(response).to have_http_status(:unauthorized)
      end

      it "returns 403 without ai.skills.update permission" do
        user_no_perm = user_with_permissions(account: account)
        post path, params: { skill_id: skill.id, successful: true }.to_json,
             headers: auth_headers_for(user_no_perm)

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  # ===================================================================
  # 5. Optimization & Maintenance
  # ===================================================================
  describe "Optimization & Maintenance" do
    describe "POST /api/v1/ai/skill_graph/optimize" do
      let(:path) { "/api/v1/ai/skill_graph/optimize" }
      let(:user) { user_with_permissions("ai.knowledge_graph.manage", account: account) }
      let(:headers) { auth_headers_for(user) }

      let(:optimization_result) do
        {
          daily: { conflicts_found: 2, auto_resolved: 1, skills_decayed: 0 },
          weekly: { refinements_proposed: 0, gaps_detected: {} }
        }
      end

      before do
        allow_any_instance_of(Ai::SkillGraph::OptimizationService)
          .to receive(:on_demand).and_return(optimization_result)
      end

      it "runs optimization with default full operation" do
        post path, headers: headers

        expect_success_response
      end

      it "accepts an operation parameter" do
        post path, params: { operation: "scan_conflicts" }.to_json, headers: headers

        expect_success_response
      end

      it "returns 422 when optimization fails" do
        allow_any_instance_of(Ai::SkillGraph::OptimizationService)
          .to receive(:on_demand).and_raise(StandardError, "Optimization failed")

        post path, headers: headers

        expect(response).to have_http_status(:unprocessable_content)
      end

      it "returns 401 without authentication" do
        post path, headers: { "Content-Type" => "application/json" }

        expect(response).to have_http_status(:unauthorized)
      end

      it "returns 403 without ai.knowledge_graph.manage permission" do
        user_no_perm = user_with_permissions(account: account)
        post path, headers: auth_headers_for(user_no_perm)

        expect(response).to have_http_status(:forbidden)
      end
    end

    describe "POST /api/v1/ai/skill_graph/maintenance/daily" do
      let(:path) { "/api/v1/ai/skill_graph/maintenance/daily" }
      let(:user) { user_with_permissions("ai.analytics.manage", account: account) }
      let(:headers) { auth_headers_for(user) }

      let(:daily_result) do
        {
          conflicts_found: 3,
          auto_resolved: 1,
          skills_decayed: 2,
          stats: nil,
          ran_at: Time.current.iso8601
        }
      end

      before do
        allow_any_instance_of(Ai::SkillGraph::OptimizationService)
          .to receive(:daily_maintenance).and_return(daily_result)
      end

      it "runs daily maintenance" do
        post path, headers: headers

        expect_success_response
        data = json_response_data
        expect(data["conflicts_found"]).to eq(3)
        expect(data["auto_resolved"]).to eq(1)
      end

      it "returns 401 without authentication" do
        post path, headers: { "Content-Type" => "application/json" }

        expect(response).to have_http_status(:unauthorized)
      end

      it "returns 403 without ai.analytics.manage permission" do
        user_no_perm = user_with_permissions(account: account)
        post path, headers: auth_headers_for(user_no_perm)

        expect(response).to have_http_status(:forbidden)
      end

      it "returns 403 when user has ai.skills.read but not ai.analytics.manage" do
        user_read = user_with_permissions("ai.skills.read", account: account)
        post path, headers: auth_headers_for(user_read)

        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
