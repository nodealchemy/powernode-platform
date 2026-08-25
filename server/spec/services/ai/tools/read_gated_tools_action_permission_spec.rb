# frozen_string_literal: true

require "rails_helper"

# G4 — the read-to-write escalation on the MCP surface.
#
# THE MEASUREMENT THAT MOTIVATES THIS. 60 MCP tool classes carry a
# REQUIRED_PERMISSION. Only 6 have a per-action ACTION_PERMISSIONS map; 40 are
# multi-action with none, and 13 of those bundle write or destructive verbs
# behind a single coarse permission. Four are the sharp end, because the coarse
# permission they bundle everything behind is a READ one:
#
#   MemoryTool           ai.agents.read -> delete_memory_pool, delete_shared_memory,
#                                          write_shared_memory, create_memory_pool
#   SharedKnowledgeTool  ai.agents.read -> delete_knowledge, update_knowledge,
#                                          create_knowledge, promote_knowledge
#   CodeMemoryTool       ai.agents.read -> prune_stale, bulk_index, upsert_node
#   LearningTool         ai.agents.read -> create_learning, reinforce_learning
#
# None of these four performs ANY permission check of its own — verified by
# grep: no has_permission?, no internal?, no instance_authorized? arm. The
# registrar's coarse enforce_permission! is the only gate, so holding
# `ai.agents.read` is sufficient to destroy shared knowledge, drop memory pools
# and prune the code graph.
#
# This is the same shape as IMP-6fbfeff384fa (sibling_tools_action_permission_spec)
# and IMP-e8adfcfcab9b, and takes the same fix: a floor constant the registrar
# enforces for the whole class, plus an ACTION_PERMISSIONS map the tool enforces
# against the action that actually RUNS — never against the invoked NAME, since
# a user principal is not pinned to it (McpPlatformToolRegistrar
# #action_pinned_to_name?) and can supply a sibling :action.
#
# ORACLES ARE ROWS, NOT STRINGS. Each refusal asserts the record survived (or
# was never created). A message-only assertion cannot tell a gate from a
# coincidental domain error, and this session has repeatedly been burned by
# exactly that gap.
RSpec.describe "read-gated MCP tools: per-action authorization" do
  let(:account) { create(:account) }

  # The first user in an account gets the OWNER role, so every actor declares
  # its permissions explicitly.
  let!(:owner)  { create(:user, account: account) }
  let(:reader)  { create(:user, account: account, permissions: %w[ai.agents.read]) }
  # The write permissions are the REST twins', not invented: SharedKnowledge
  # writes map to ai.memory.write (TieredMemoryController), memory pools to
  # ai.memory_pools.manage (MemoryPoolsController#authorize_manage!), learning
  # writes to ai.analytics.manage (LearningController) and code-graph writes to
  # ai.knowledge_graph.manage (KnowledgeGraphController).
  let(:writer) do
    create(:user, account: account,
                  permissions: %w[ai.agents.read ai.memory.write ai.memory_pools.manage
                                  ai.analytics.manage ai.knowledge_graph.manage])
  end

  def run(tool_name, params = {}, user:)
    ::Ai::Tools::McpPlatformToolRegistrar.execute_tool(
      "platform.#{tool_name}", params: params, account: account, user: user, mcp_agent: nil
    )
  end

  # A refusal is a refusal whether it surfaces as an error result or a raise.
  def refuse(tool_name, params = {}, user:)
    run(tool_name, params, user: user)
  rescue ::Mcp::ProtocolService::PermissionDeniedError => e
    { success: false, error: e.message }
  end

  def expect_refused(result)
    expect(result[:success]).to be_falsey
    expect(result[:error].to_s).to match(/permission|denied|requires/i)
  end

  describe "Ai::Tools::SharedKnowledgeTool" do
    let!(:entry) do
      ::Ai::SharedKnowledge.create!(
        account: account, title: "t", content: "c",
        content_type: "fact", access_level: "team"
      )
    end

    it "refuses a hard delete_knowledge from a reader, and the entry survives" do
      result = nil

      expect {
        result = refuse("delete_knowledge",
                        { "entry_id" => entry.id, "hard_delete" => true }, user: reader)
      }.not_to change { ::Ai::SharedKnowledge.where(account_id: account.id).count }

      expect_refused(result)
      expect(::Ai::SharedKnowledge.find_by(id: entry.id)).to be_present
    end

    it "refuses create_knowledge from a reader and writes no row" do
      result = nil

      expect {
        result = refuse("create_knowledge",
                        { "title" => "x", "content" => "y", "content_type" => "fact" },
                        user: reader)
      }.not_to change { ::Ai::SharedKnowledge.where(account_id: account.id).count }

      expect_refused(result)
    end

    # Over-gating oracle: passes on unmodified HEAD (nothing is gated) and
    # exists solely to catch a floor that locks legitimate readers out of the
    # benign action the coarse permission was always meant to grant.
    it "still lets a reader search_knowledge" do
      result = run("search_knowledge", { "query" => "t" }, user: reader)

      expect(result[:error].to_s).not_to match(/permission|denied|requires/i)
    end
  end

  describe "Ai::Tools::MemoryTool" do
    let!(:pool) do
      account.ai_memory_pools.create!(
        pool_id: "g4-pool", name: "G4 Pool", pool_type: "shared", scope: "persistent"
      )
    end

    it "refuses delete_memory_pool from a reader, and the pool survives" do
      result = nil

      expect {
        result = refuse("delete_memory_pool", { "pool_id" => "g4-pool" }, user: reader)
      }.not_to change { account.ai_memory_pools.count }

      expect_refused(result)
      expect(account.ai_memory_pools.find_by(pool_id: "g4-pool")).to be_present
    end

    it "still lets a reader list_pools" do
      result = run("list_pools", {}, user: reader)

      expect(result[:error].to_s).not_to match(/permission|denied|requires/i)
    end
  end

  describe "Ai::Tools::LearningTool" do
    it "refuses create_learning from a reader and writes no row" do
      result = nil

      expect {
        result = refuse("create_learning",
                        { "content" => "some learning", "category" => "discovery" },
                        user: reader)
      }.not_to change { ::Ai::CompoundLearning.count }

      expect_refused(result)
    end

    it "still lets a reader query_learnings" do
      result = run("query_learnings", { "query" => "x" }, user: reader)

      expect(result[:error].to_s).not_to match(/permission|denied|requires/i)
    end
  end

  # Added because mutating ONLY CodeMemoryTool's gate reddened NOTHING: the gate
  # was applied but unpinned. Mutating each tool separately is what surfaced it —
  # a shared helper means one mutation can otherwise mask three.
  # NOTE the registered NAME is code_upsert_node; McpPlatformToolRegistrar
  # ACTION_ALIASES maps it to the internal action `upsert_node`, which is what
  # ACTION_PERMISSIONS is keyed on — the action that RUNS, not the name invoked.
  describe "Ai::Tools::CodeMemoryTool" do
    it "refuses upsert_node from a reader and writes no graph node" do
      result = nil

      expect {
        result = refuse("code_upsert_node",
                        { "name" => "G4::Probe", "entity_type" => "class" },
                        user: reader)
      }.not_to change { ::Ai::KnowledgeGraphNode.where(account_id: account.id).count }

      expect_refused(result)
    end

    it "still lets a reader search_graph" do
      result = run("code_search_graph", { "query" => "G4" }, user: reader)

      expect(result[:error].to_s).not_to match(/permission|denied|requires/i)
    end
  end

  # ── Escalations behind a WRITE floor (G4 tail) ─────────────────────────────
  #
  # These two do not sit behind a READ permission, so they are less severe than
  # the four above — but the floor is still WEAKER than the action needs, which
  # is the same defect in a smaller size. Nine tools bundle writes behind one
  # coarse permission; only these two put a DESTRUCTIVE action behind a verb
  # that the REST twin does not accept for it. The rest are granularity (their
  # floor is already the `manage`-class verb) and are deliberately not touched.
  describe "Ai::Tools::AgentManagementTool" do
    # REST twin: Ai::AgentHelpers#validate_permissions maps destroy ->
    # ai.agents.delete, create -> ai.agents.create, update -> ai.agents.update.
    # The tool's floor is ai.agents.execute, which REST accepts only for
    # execute/test/pause/resume/archive — never for deleting an agent.
    let(:executor) { create(:user, account: account, permissions: %w[ai.agents.execute]) }
    let!(:victim)  { create(:ai_agent, account: account) }

    it "refuses delete_agent from an execute-only holder, and the agent survives" do
      result = nil

      expect {
        result = refuse("delete_agent", { "agent_id" => victim.id }, user: executor)
      }.not_to change { ::Ai::Agent.where(account_id: account.id).count }

      expect_refused(result)
      expect(::Ai::Agent.find_by(id: victim.id)).to be_present
    end
  end

  describe "Ai::Tools::RalphLoopTool" do
    # REST twin: RalphLoopsController maps destroy -> ai.loops.delete,
    # update -> ai.loops.update, start/pause/resume/cancel/reset ->
    # ai.loops.execute. The tool's floor is ai.agents.update — a DIFFERENT
    # NAMESPACE entirely, so holding an agent permission deletes loops.
    let(:agent_updater) { create(:user, account: account, permissions: %w[ai.agents.update]) }
    let!(:loop_row) { create(:ai_ralph_loop, account: account) }

    it "refuses delete_ralph_loop from an ai.agents.update holder, and the loop survives" do
      result = nil

      expect {
        result = refuse("delete_ralph_loop", { "loop_id" => loop_row.id }, user: agent_updater)
      }.not_to change { ::Ai::RalphLoop.where(account_id: account.id).count }

      expect_refused(result)
      expect(::Ai::RalphLoop.find_by(id: loop_row.id)).to be_present
    end

    it "permits delete_ralph_loop for a holder of ai.loops.delete" do
      loops_admin = create(:user, account: account,
                                  permissions: %w[ai.agents.update ai.loops.delete])

      result = run("delete_ralph_loop", { "loop_id" => loop_row.id }, user: loops_admin)

      expect(result[:error].to_s).not_to match(/permission|denied|requires/i)
    end
  end

  # The escalation is only closed if the WRITE permission actually opens the
  # write actions again — otherwise the fix is just a wall.
  describe "a holder of the write permission is not locked out" do
    let!(:entry) do
      ::Ai::SharedKnowledge.create!(
        account: account, title: "t2", content: "c2",
        content_type: "fact", access_level: "team"
      )
    end

    it "permits delete_knowledge for a writer" do
      result = run("delete_knowledge",
                   { "entry_id" => entry.id, "hard_delete" => true }, user: writer)

      expect(result[:error].to_s).not_to match(/permission|denied|requires/i)
    end
  end
end
