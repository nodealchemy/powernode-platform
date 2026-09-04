# frozen_string_literal: true

require "rails_helper"

# HIER-P0 — the Autonomy page's lineage surface must be TRUTHFUL.
#
# Two defects on HEAD before this spec:
#   * the forest read `current_account.ai_agents`, which excludes every GLOBAL
#     platform agent (account_id NULL) — the 23 canonical agents on ops-hub were
#     invisible while the picker (built from account-scoped trust scores) listed
#     them, so selecting one rendered nothing the forest could show;
#   * the single-agent endpoint returned `{agent_id, children, parents, ...}`
#     while AutonomyDashboardPage feeds that payload straight into
#     AgentLineageTree, which reads `{id, name, type, status, children}` — so a
#     selected agent rendered as a nameless node.
RSpec.describe "Api::V1::Ai::Autonomy lineage", type: :request do
  let(:account)  { create(:account) }
  let(:other_account) { create(:account) }
  let(:provider) { create(:ai_provider, account: account) }
  let(:user)     { create(:user, account: account, permissions: %w[ai.agents.read]) }
  let(:headers)  { auth_headers_for(user) }

  # A GLOBAL canonical agent: account_id NULL, is_system, source_key-managed.
  let!(:canonical_agent) do
    create(:ai_agent, account: nil, name: "System Concierge", agent_type: "assistant",
                      source_key: "system-concierge", is_system: true,
                      creator: user, provider: provider, status: "active")
  end

  # An ACCOUNT clone of the canonical (the only way an official agent enters an
  # account under the canonical rule).
  let!(:account_clone) do
    create(:ai_agent, account: account, name: "Concierge (ours)", agent_type: "assistant",
                      cloned_from: canonical_agent, creator: user, provider: provider, status: "active")
  end

  # A parent/child pair with a real lineage row, so the forest has one tree.
  let!(:parent_agent) { create(:ai_agent, account: account, name: "Ops Manager", agent_type: "monitor", creator: user, provider: provider) }
  let!(:child_agent)  { create(:ai_agent, account: account, name: "Ops Worker", agent_type: "data_analyst", creator: user, provider: provider) }
  let!(:lineage)      { create(:ai_agent_lineage, account: account, parent_agent: parent_agent, child_agent: child_agent) }

  # Another account's agent must never leak into this account's forest.
  let!(:foreign_agent) do
    create(:ai_agent, account: other_account, name: "Someone Else",
                      creator: create(:user, account: other_account),
                      provider: create(:ai_provider, account: other_account))
  end

  def get_json(path)
    get path, headers: headers, as: :json
    expect(response).to have_http_status(:ok), response.body
    response.parsed_body.fetch("data")
  end

  describe "GET /api/v1/ai/autonomy/lineage (forest)" do
    let(:data) { get_json("/api/v1/ai/autonomy/lineage") }
    let(:orphan_ids) { data.fetch("orphans").map { |o| o["id"] } }
    let(:tree_ids)   { data.fetch("trees").map { |t| t["id"] } }

    it "includes the global canonical agent as a root agent, flagged canonical" do
      expect(orphan_ids).to include(canonical_agent.id)

      node = data["orphans"].find { |o| o["id"] == canonical_agent.id }
      expect(node).to include("name" => "System Concierge", "type" => "assistant", "canonical" => true)
    end

    it "includes the account's clone of the canonical, not flagged canonical" do
      expect(orphan_ids).to include(account_clone.id)

      node = data["orphans"].find { |o| o["id"] == account_clone.id }
      expect(node).to include("name" => "Concierge (ours)", "canonical" => false)
    end

    it "roots a real lineage tree at the parent and keeps the child out of the root list" do
      expect(tree_ids).to eq([parent_agent.id])

      tree = data["trees"].first
      expect(tree).to include("name" => "Ops Manager", "depth" => 0, "canonical" => false)
      expect(tree["children"].map { |c| c["id"] }).to eq([child_agent.id])
      expect(tree["children"].first).to include("name" => "Ops Worker", "depth" => 1)

      expect(orphan_ids).not_to include(parent_agent.id)
      expect(orphan_ids).not_to include(child_agent.id)
    end

    it "never shows another account's agent" do
      expect(orphan_ids + tree_ids).not_to include(foreign_agent.id)
    end

    it "lists every root agent as a node the tree can render" do
      (data["orphans"] + data["trees"]).each do |node|
        expect(node.keys).to include("id", "name", "type", "status", "depth", "children", "canonical")
      end
    end
  end

  describe "GET /api/v1/ai/autonomy/lineage/:agent_id (single agent)" do
    it "returns an AgentLineageNode rooted at the agent, with parents as sibling data" do
      data = get_json("/api/v1/ai/autonomy/lineage/#{parent_agent.id}")

      expect(data).to include(
        "id" => parent_agent.id, "name" => "Ops Manager", "type" => "monitor",
        "status" => "active", "depth" => 0, "canonical" => false
      )
      expect(data["children"].map { |c| c["id"] }).to eq([child_agent.id])
      expect(data["children"].first).to include("name" => "Ops Worker", "depth" => 1)
      expect(data["parents"]).to eq([])
    end

    it "names the parents of a child agent" do
      data = get_json("/api/v1/ai/autonomy/lineage/#{child_agent.id}")

      expect(data).to include("id" => child_agent.id, "name" => "Ops Worker")
      expect(data["children"]).to eq([])
      expect(data["parents"]).to contain_exactly(
        a_hash_including("id" => parent_agent.id, "name" => "Ops Manager", "type" => "monitor")
      )
    end

    it "keeps the legacy counters under meta rather than at the top level" do
      data = get_json("/api/v1/ai/autonomy/lineage/#{parent_agent.id}")

      expect(data["meta"]).to include("agent_id" => parent_agent.id, "total_children" => 1, "total_parents" => 0)
      expect(data.keys).not_to include("agent_id", "total_children", "total_parents")
    end

    it "resolves a global canonical agent and flags it" do
      data = get_json("/api/v1/ai/autonomy/lineage/#{canonical_agent.id}")

      expect(data).to include("id" => canonical_agent.id, "name" => "System Concierge", "canonical" => true)
    end

    it "does not resolve another account's agent" do
      get "/api/v1/ai/autonomy/lineage/#{foreign_agent.id}", headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end
end
