# frozen_string_literal: true

require "rails_helper"

# c13-2 batch C-A. Eight destroy-shaped knowledge, memory and RAG verbs were
# declared `destructive: true` but armed no gate, so a user principal (and the
# whole-server grant) ran them directly. Each now parks behind the autonomy gate
# as a require_approval deferred tool call, and runs only on the replay of an
# approval. Every example asserts the ROW as well as the envelope: a refusal
# that writes anyway passes an envelope-shaped assertion.
RSpec.describe "c13-2 batch C-A destructive verbs park", type: :service do
  let(:account) { create(:account) }
  let(:user) do
    create(:user, account: account,
                  permissions: %w[ai.memory.write ai.memory_pools.manage ai.knowledge.manage])
  end

  after { ::Mcp::Principal.reset! }

  def park(tool_class, params)
    tool = tool_class.new(account: account, user: user)
    tool.call_origin = "mcp_oauth"
    tool.execute(params: params.with_indifferent_access)
  end

  def expect_parked(result, category)
    expect(result).to include(success: true)
    expect(result[:data]).to include(pending: true)
    operation = Ai::DeferredOperation.find(result[:data][:deferred_operation_id])
    expect(operation.action_category).to eq(category)
    expect(operation.executor_class).to eq("Ai::Executors::DeferredToolCall")
    # All eight are destructive: true, so the approver must be a person in their
    # own session (HumanSessionPolicy rule 4), not a tool door, even though the
    # verbs are plain require_approval and not human_only.
    expect(Ai::ApprovalRequest.find(result[:data][:approval_request_id]).requires_human_session?).to be(true)
  end

  it "parks delete_knowledge, leaving the entry in place (hard_delete too)" do
    entry = create(:ai_shared_knowledge, account: account)

    expect_parked(park(Ai::Tools::SharedKnowledgeTool,
                       action: "delete_knowledge", entry_id: entry.id, hard_delete: true),
                  "ai.knowledge.delete")
    expect(Ai::SharedKnowledge.where(id: entry.id)).to exist
    expect(entry.reload.provenance["archived"]).not_to eq(true)
  end

  it "parks archive_by_predicate, archiving nothing even with dry_run: false" do
    entry = create(:ai_shared_knowledge, account: account, source_type: "import")

    expect_parked(park(Ai::Tools::SharedKnowledgeTool,
                       action: "archive_by_predicate", source_type: "import", dry_run: false),
                  "ai.knowledge.archive_bulk")
    expect(entry.reload.provenance["archived"]).not_to eq(true)
  end

  it "parks hard_delete_archived, destroying nothing even with dry_run: false" do
    archived = create(:ai_shared_knowledge, account: account, provenance: { "archived" => true })

    expect_parked(park(Ai::Tools::SharedKnowledgeTool, action: "hard_delete_archived", dry_run: false),
                  "ai.knowledge.hard_delete_bulk")
    expect(Ai::SharedKnowledge.where(id: archived.id)).to exist
  end

  it "parks retire_by_predicate, retiring nothing even with dry_run: false" do
    learning = create(:ai_compound_learning, account: account, status: "active", extraction_method: "gate_spec")

    expect_parked(park(Ai::Tools::LearningTool,
                       action: "retire_by_predicate", extraction_method: "gate_spec", dry_run: false),
                  "ai.learning.retire_bulk")
    expect(learning.reload.status).to eq("active")
  end

  it "parks hard_delete_retired, destroying nothing even with dry_run: false" do
    retired = create(:ai_compound_learning, :retired, account: account, extraction_method: "gate_spec")

    expect_parked(park(Ai::Tools::LearningTool,
                       action: "hard_delete_retired", extraction_method: "gate_spec", dry_run: false),
                  "ai.learning.hard_delete_bulk")
    expect(Ai::CompoundLearning.where(id: retired.id)).to exist
  end

  it "parks delete_memory_pool, leaving the pool in place" do
    pool = create(:ai_memory_pool, account: account)

    expect_parked(park(Ai::Tools::MemoryTool, action: "delete_memory_pool", pool_id: pool.pool_id),
                  "ai.memory_pool.delete")
    expect(Ai::MemoryPool.where(id: pool.id)).to exist
  end

  it "parks delete_shared_memory, leaving the pool untouched" do
    pool = create(:ai_memory_pool, account: account)
    before = pool.reload.attributes

    expect_parked(park(Ai::Tools::MemoryTool, action: "delete_shared_memory", pool_id: pool.pool_id, key: "k"),
                  "ai.memory.shared_delete")
    expect(pool.reload.attributes).to eq(before)
  end

  it "parks delete_document, leaving the document in place" do
    kb = create(:ai_knowledge_base, account: account)
    document = create(:ai_document, knowledge_base: kb)

    expect_parked(park(Ai::Tools::RagManagementTool,
                       action: "delete_document", knowledge_base_id: kb.id, document_id: document.id),
                  "ai.document.delete")
    expect(Ai::Document.where(id: document.id)).to exist
  end

  # A gated action never reaches #call, where these tools check the per-action
  # permission, so each declares #authorization_error: a caller without the
  # permission is refused and nothing is parked for anyone to approve.
  describe "a caller without the action's permission" do
    let(:reader) { create(:user, account: account, permissions: %w[ai.agents.read]) }

    [
      [ Ai::Tools::SharedKnowledgeTool, "delete_knowledge", { entry_id: "x" } ],
      [ Ai::Tools::SharedKnowledgeTool, "archive_by_predicate", { source_type: "import", dry_run: false } ],
      [ Ai::Tools::SharedKnowledgeTool, "hard_delete_archived", { dry_run: false } ],
      [ Ai::Tools::LearningTool, "retire_by_predicate", { extraction_method: "x", dry_run: false } ],
      [ Ai::Tools::LearningTool, "hard_delete_retired", { extraction_method: "x", dry_run: false } ],
      [ Ai::Tools::MemoryTool, "delete_memory_pool", { pool_id: "p" } ],
      [ Ai::Tools::MemoryTool, "delete_shared_memory", { pool_id: "p", key: "k" } ]
    ].each do |tool_class, action, extra|
      it "is refused #{action} and parks nothing" do
        tool = tool_class.new(account: account, user: reader)
        tool.call_origin = "mcp_oauth"

        result = tool.execute(params: { action: action }.merge(extra).with_indifferent_access)

        expect(result[:success]).to be(false)
        expect(result[:error]).to match(/permission denied/)
        expect(Ai::DeferredOperation.count).to eq(0)
        expect(Ai::ApprovalRequest.count).to eq(0)
      end
    end
  end
end
