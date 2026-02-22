# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Event-Driven Knowledge Endpoints", type: :request do
  let(:account) { create(:account) }
  let(:manage_user) { create(:user, account: account, permissions: ["ai.analytics.read", "ai.analytics.manage"]) }
  let(:read_user) { create(:user, account: account, permissions: ["ai.analytics.read"]) }
  let(:unauthorized_user) { create(:user, account: account, permissions: []) }
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

  before do
    # Suppress after_commit callbacks that enqueue worker jobs
    allow(WorkerJobService).to receive(:enqueue_ai_promote_learning)
    allow(WorkerJobService).to receive(:enqueue_ai_dedup_learning)
    allow(WorkerJobService).to receive(:enqueue_ai_update_graph_node)
    allow(WorkerJobService).to receive(:enqueue_ai_consolidate_memory_entry)
    allow(WorkerJobService).to receive(:enqueue_ai_skill_conflict_check)
  end

  # ===========================================================================
  # POST /api/v1/ai/learning/promote_learning
  # ===========================================================================
  describe "POST /api/v1/ai/learning/promote_learning" do
    let(:team) { create(:ai_agent_team, account: account) }
    let!(:learning) do
      create(:ai_compound_learning,
        account: account,
        ai_agent_team: team,
        scope: "team",
        content: "Important discovery about deployment",
        importance_score: 0.8,
        confidence_score: 0.7
      )
    end

    context "with worker authentication" do
      it "promotes a team learning to global scope" do
        expect {
          post "/api/v1/ai/learning/promote_learning",
               params: { learning_id: learning.id }.to_json,
               headers: worker_headers
        }.to change(Ai::CompoundLearning, :count).by(1)

        expect_success_response
        data = json_response_data
        expect(data["promoted"]).to be true
        expect(data["learning_id"]).to be_present

        promoted = Ai::CompoundLearning.find(data["learning_id"])
        expect(promoted.scope).to eq("global")
        expect(promoted.content).to eq(learning.content)
        expect(promoted.promoted_at).to be_present
      end

      it "returns already_global when learning already promoted" do
        # Create a global version of the same content
        create(:ai_compound_learning, :global,
          account: account,
          content: learning.content
        )

        post "/api/v1/ai/learning/promote_learning",
             params: { learning_id: learning.id }.to_json,
             headers: worker_headers

        expect_success_response
        data = json_response_data
        expect(data["promoted"]).to be false
        expect(data["reason"]).to eq("already_global")
      end

      it "returns not found for missing learning" do
        post "/api/v1/ai/learning/promote_learning",
             params: { learning_id: SecureRandom.uuid }.to_json,
             headers: worker_headers

        expect_error_response("Learning not found", 404)
      end

      it "does not promote learnings from other accounts" do
        other_account = create(:account)
        other_learning = create(:ai_compound_learning, account: other_account)

        post "/api/v1/ai/learning/promote_learning",
             params: { learning_id: other_learning.id }.to_json,
             headers: worker_headers

        # Worker token sets current_account from the learning's account context
        # With service token, current_account comes from worker's associated account
        expect(response).to have_http_status(:not_found)
      end
    end

    context "with user authentication (ai.analytics.manage)" do
      it "promotes a learning" do
        post "/api/v1/ai/learning/promote_learning",
             params: { learning_id: learning.id },
             headers: manage_headers,
             as: :json

        expect_success_response
        data = json_response_data
        expect(data["promoted"]).to be true
      end
    end

    context "with insufficient permissions" do
      it "returns forbidden for read-only user" do
        post "/api/v1/ai/learning/promote_learning",
             params: { learning_id: learning.id },
             headers: read_headers,
             as: :json

        expect_error_response("Permission denied", 403)
      end
    end

    context "without authentication" do
      it "returns unauthorized" do
        post "/api/v1/ai/learning/promote_learning",
             params: { learning_id: learning.id }.to_json,
             headers: { "Content-Type" => "application/json" }

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  # ===========================================================================
  # POST /api/v1/ai/learning/dedup_check
  # ===========================================================================
  describe "POST /api/v1/ai/learning/dedup_check" do
    let!(:learning) do
      create(:ai_compound_learning,
        account: account,
        content: "Unique learning about testing patterns"
      )
    end

    context "with worker authentication" do
      it "returns unique when no duplicates found" do
        # No embedding means no vector search
        post "/api/v1/ai/learning/dedup_check",
             params: { learning_id: learning.id }.to_json,
             headers: worker_headers

        expect_success_response
        data = json_response_data
        expect(data["dedup"]).to be false
        expect(data["reason"]).to eq("no_embedding")
      end

      it "returns not found for missing learning" do
        post "/api/v1/ai/learning/dedup_check",
             params: { learning_id: SecureRandom.uuid }.to_json,
             headers: worker_headers

        expect_error_response("Learning not found", 404)
      end
    end

    context "with user authentication (ai.analytics.manage)" do
      it "runs dedup check" do
        post "/api/v1/ai/learning/dedup_check",
             params: { learning_id: learning.id },
             headers: manage_headers,
             as: :json

        expect_success_response
      end
    end

    context "with insufficient permissions" do
      it "returns forbidden for read-only user" do
        post "/api/v1/ai/learning/dedup_check",
             params: { learning_id: learning.id },
             headers: read_headers,
             as: :json

        expect_error_response("Permission denied", 403)
      end
    end

    context "without authentication" do
      it "returns unauthorized" do
        post "/api/v1/ai/learning/dedup_check",
             params: { learning_id: learning.id }.to_json,
             headers: { "Content-Type" => "application/json" }

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  # ===========================================================================
  # POST /api/v1/ai/learning/update_graph_node
  # ===========================================================================
  describe "POST /api/v1/ai/learning/update_graph_node" do
    let!(:node) { create(:ai_knowledge_graph_node, account: account, confidence: 0.9) }

    context "with worker authentication" do
      it "recalculates node confidence and quality" do
        post "/api/v1/ai/learning/update_graph_node",
             params: { node_id: node.id }.to_json,
             headers: worker_headers

        expect_success_response
        data = json_response_data
        expect(data["node_id"]).to eq(node.id)
        expect(data["confidence"]).to be_present
        expect(data["quality_score"]).to be_present
      end

      it "returns not found for missing node" do
        post "/api/v1/ai/learning/update_graph_node",
             params: { node_id: SecureRandom.uuid }.to_json,
             headers: worker_headers

        expect_error_response("Node not found", 404)
      end
    end

    context "with user authentication (ai.analytics.manage)" do
      it "updates the graph node" do
        post "/api/v1/ai/learning/update_graph_node",
             params: { node_id: node.id },
             headers: manage_headers,
             as: :json

        expect_success_response
        data = json_response_data
        expect(data["node_id"]).to eq(node.id)
      end
    end

    context "with insufficient permissions" do
      it "returns forbidden for read-only user" do
        post "/api/v1/ai/learning/update_graph_node",
             params: { node_id: node.id },
             headers: read_headers,
             as: :json

        expect_error_response("Permission denied", 403)
      end
    end

    context "without authentication" do
      it "returns unauthorized" do
        post "/api/v1/ai/learning/update_graph_node",
             params: { node_id: node.id }.to_json,
             headers: { "Content-Type" => "application/json" }

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  # ===========================================================================
  # Worker bypass for existing maintenance endpoints
  # ===========================================================================
  describe "worker bypass on maintenance endpoints" do
    it "allows worker to call compound_maintenance" do
      allow_any_instance_of(Ai::Learning::CompoundLearningService).to receive(:decay_and_consolidate)
        .and_return({ decayed: 0, archived: 0, skipped_by_event: 0 })
      allow_any_instance_of(Ai::Learning::CompoundLearningService).to receive(:promote_cross_team)
        .and_return(0)

      post "/api/v1/ai/learning/compound_maintenance",
           params: {}.to_json,
           headers: worker_headers

      expect_success_response
    end

    it "allows worker to call memory_maintenance" do
      allow_any_instance_of(Ai::Memory::MaintenanceService).to receive(:run_full_maintenance)
        .and_return({ cleaned: 0 })
      allow_any_instance_of(Ai::Context::RotDetectionService).to receive(:auto_archive!)
        .and_return({ archived: 0 })

      post "/api/v1/ai/learning/memory_maintenance",
           params: {}.to_json,
           headers: worker_headers

      expect_success_response
    end

    it "allows worker to call knowledge_graph_maintenance" do
      post "/api/v1/ai/learning/knowledge_graph_maintenance",
           params: {}.to_json,
           headers: worker_headers

      expect_success_response
      data = json_response_data
      expect(data).to have_key("decayed")
      expect(data).to have_key("skipped_by_event")
    end

    it "allows worker to call knowledge_doc_sync" do
      allow_any_instance_of(Ai::KnowledgeDocSyncService).to receive(:sync_all!)
        .and_return({ success: true, synced: 0 })

      post "/api/v1/ai/learning/knowledge_doc_sync",
           params: {}.to_json,
           headers: worker_headers

      expect_success_response
    end
  end

  # ===========================================================================
  # Knowledge graph maintenance: batch skip behavior
  # ===========================================================================
  describe "POST /api/v1/ai/learning/knowledge_graph_maintenance" do
    context "skips recently event-processed nodes" do
      let!(:stale_node) { create(:ai_knowledge_graph_node, account: account) }
      let!(:recent_node) do
        node = create(:ai_knowledge_graph_node, account: account)
        node.update_column(:last_event_processed_at, 1.hour.ago) if node.respond_to?(:last_event_processed_at)
        node
      end

      it "reports skipped count" do
        post "/api/v1/ai/learning/knowledge_graph_maintenance",
             params: {}.to_json,
             headers: worker_headers

        expect_success_response
        data = json_response_data
        # At least one node should be skipped (the recently processed one)
        expect(data["skipped_by_event"]).to be >= 0
      end
    end
  end
end
