# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Tools::AgentManagementTool do
  let(:account) { create(:account) }
  # Behaviour examples; the actor holds what the REST twin requires for these
  # actions (Ai::AgentHelpers: create -> ai.agents.create, update ->
  # ai.agents.update, destroy -> ai.agents.delete, execute -> ai.agents.execute).
  # Authorization is pinned separately in
  # read_gated_tools_action_permission_spec.rb.
  let(:user) do
    create(:user, account: account,
                  permissions: %w[ai.agents.read ai.agents.execute ai.agents.create
                                  ai.agents.update ai.agents.delete])
  end
  let!(:provider) { create(:ai_provider, account: account, is_active: true) }
  let(:tool) { described_class.new(account: account, user: user) }

  describe ".definition" do
    it "returns a valid tool definition" do
      defn = described_class.definition
      expect(defn[:name]).to eq("agent_management")
      expect(defn[:description]).to be_present
      expect(defn[:parameters]).to include(:action, :agent_id, :name, :description, :model, :input)
    end

    it "marks action as required" do
      expect(described_class.definition[:parameters][:action][:required]).to be true
    end
  end

  describe ".permitted?" do
    it "requires ai.agents.execute permission" do
      expect(described_class::REQUIRED_PERMISSION).to eq("ai.agents.execute")
    end
  end

  describe "#execute" do
    context "with create_agent action" do
      # An ai.agents.create holder creates by CLONING a seeded canonical
      # (canonical rule, HIER-P1 — see the context below for the free-form path).
      let!(:template) do
        create(:ai_agent, account: nil, name: "Template Agent", agent_type: "assistant", is_system: true,
                          source_key: "template-agent", provider: provider, creator: create(:user, account: account))
      end

      it "creates an agent for the account" do
        result = tool.execute(params: { action: "create_agent", canonical_slug: "template-agent",
                                        name: "Test Agent", description: "A test" })
        expect(result[:success]).to be true
        expect(result[:agent_id]).to be_present
        expect(result[:name]).to eq("Test Agent")
        expect(Ai::Agent.find(result[:agent_id]).description).to eq("A test")
      end

      it "returns error on invalid record" do
        result = tool.execute(params: { action: "create_agent", canonical_slug: "template-agent", name: "" })
        expect(result[:success]).to be false
        expect(result[:error]).to be_present
      end
    end

    # HIER-P1 canonical rule (operator ruling 2026-09-03 §5): official agents
    # are seeded GLOBAL canonicals; a new agent is a clone of one into the
    # account, with lineage written at clone time. A free-form agent (no
    # canonical) needs ai.agents.manage; ai.agents.create alone clones only.
    context "create_agent under the canonical rule" do
      let!(:canonical) do
        create(:ai_agent, account: nil, name: "Research Analyst", agent_type: "data_analyst",
                          is_system: true, source_key: "research-analyst", provider: provider,
                          creator: create(:user, account: account))
      end

      it "refuses a free-form agent for an ai.agents.create holder and names the rule" do
        expect {
          result = tool.execute(params: { action: "create_agent", name: "Free Form" })
          expect(result[:success]).to be false
          expect(result[:error]).to match(/canonical_slug/)
          expect(result[:error]).to match(/ai\.agents\.manage/)
        }.not_to change(Ai::Agent, :count)
      end

      it "clones the canonical into the account with provenance and a lineage edge to it" do
        result = tool.execute(params: { action: "create_agent", canonical_slug: "research-analyst",
                                        name: "Team Analyst" })

        expect(result[:success]).to be true
        agent = Ai::Agent.find(result[:agent_id])
        expect(agent.account_id).to eq(account.id)
        expect(agent.name).to eq("Team Analyst")
        expect(agent.cloned_from_id).to eq(canonical.id)
        expect(agent.source_key).to eq("research-analyst")
        expect(agent.source_version).to eq(canonical.version)
        expect(agent.source_snapshot).to be_present
        expect(agent.is_system).to be false
        expect(agent.parent_agent_id).to eq(canonical.id)

        edges = Ai::AgentLineage.for_child(agent.id).active
        expect(edges.pluck(:parent_agent_id)).to eq([ canonical.id ])
        expect(edges.first.account_id).to eq(account.id)
        expect(result[:cloned_from_id]).to eq(canonical.id)
      end

      it "reports an unknown canonical_slug instead of falling back to a free-form create" do
        expect {
          result = tool.execute(params: { action: "create_agent", canonical_slug: "no-such-agent", name: "X" })
          expect(result[:success]).to be false
          expect(result[:error]).to match(/no-such-agent/)
        }.not_to change(Ai::Agent, :count)
      end

      # REACHABILITY, not a stub: the escape hatch is satisfied through a real
      # role grant. `ai.agents.manage` is not in the Permissions catalog (see
      # config/permissions.rb — RolePermission refuses to grant an undefined
      # name), so today the only principal that satisfies it is a system.admin
      # holder, for whom User#has_permission? returns true for every name.
      # Registering the permission is a follow-up owned by the catalog.
      context "when the caller really holds the free-form permission (system.admin)" do
        before do
          role = create(:role, account: account)
          role.role_permissions.create!(permission_name: "system.admin")
          user.roles << role
          expect(user.has_permission?("ai.agents.manage")).to be true
        end

        it "creates the free-form agent and attaches it to the invoking agent" do
          invoking = create(:ai_agent, account: account, name: "Designer")
          tool = described_class.new(account: account, user: user, agent: invoking)

          result = tool.execute(params: { action: "create_agent", name: "Free Form" })

          expect(result[:success]).to be true
          agent = Ai::Agent.find(result[:agent_id])
          expect(agent.cloned_from_id).to be_nil
          expect(agent.parent_agent_id).to eq(invoking.id)
          expect(Ai::AgentLineage.for_child(agent.id).active.pluck(:parent_agent_id)).to eq([ invoking.id ])
        end

        it "attaches a free-form agent created without an invoking agent to the account's concierge" do
          concierge = create(:ai_agent, account: account, name: "Concierge", is_concierge: true)

          result = tool.execute(params: { action: "create_agent", name: "Free Form" })

          expect(result[:success]).to be true
          expect(Ai::Agent.find(result[:agent_id]).parent_agent_id).to eq(concierge.id)
        end
      end
    end

    context "with list_agents action" do
      it "returns active agents for the account" do
        create(:ai_agent, account: account, status: "active")
        create(:ai_agent, account: account, status: "active")

        result = tool.execute(params: { action: "list_agents" })
        expect(result[:success]).to be true
        expect(result[:agents].size).to eq(2)
        expect(result[:agents].first).to include(:id, :name, :model, :status)
      end

      it "does not return inactive agents" do
        create(:ai_agent, account: account, status: "active")
        create(:ai_agent, :inactive, account: account)

        result = tool.execute(params: { action: "list_agents" })
        expect(result[:agents].size).to eq(1)
      end

      it "does not return agents from other accounts" do
        other_account = create(:account)
        create(:ai_agent, account: other_account, status: "active")
        create(:ai_agent, account: account, status: "active")

        result = tool.execute(params: { action: "list_agents" })
        expect(result[:agents].size).to eq(1)
      end
    end

    context "with execute_agent action" do
      before do
        allow(WorkerJobService).to receive(:enqueue_ai_agent_execution).and_return(true)
      end

      it "queues agent execution" do
        agent = create(:ai_agent, account: account)
        result = tool.execute(params: { action: "execute_agent", agent_id: agent.id })
        expect(result[:success]).to be true
        expect(result[:status]).to eq("execution_dispatched")
      end

      it "returns error for non-existent agent" do
        result = tool.execute(params: { action: "execute_agent", agent_id: SecureRandom.uuid })
        expect(result[:success]).to be false
        expect(result[:error]).to match(/not found/i)
      end

      # Bug: execute_agent recorded the agent's RAW `provider` association on the
      # created AgentExecution instead of the RESOLVED provider that actually
      # serves the call (Ai::Agent#resolved_provider). See
      # app/models/concerns/ai/agent/execution.rb for the sibling bug/fix.
      it "records the RESOLVED provider's id, not the raw association's" do
        raw_provider = create(:ai_provider, account: account, name: "stale-ollama")
        resolved_provider = create(:ai_provider, account: account, name: "actual-anthropic")
        agent = create(:ai_agent, account: account, provider: raw_provider)
        # resolve_agent re-queries the DB for the agent, so stub resolution on
        # the class (any_instance) rather than the `agent` object created above.
        allow_any_instance_of(Ai::Agent).to receive(:resolved_provider).and_return(resolved_provider)

        result = tool.execute(params: { action: "execute_agent", agent_id: agent.id })

        expect(result[:success]).to be true
        execution = Ai::AgentExecution.find(result[:execution_id])
        expect(execution.ai_provider_id).to eq(resolved_provider.id)
        expect(execution.ai_provider_id).not_to eq(raw_provider.id)
      end
    end

    context "with unknown action" do
      it "returns error" do
        result = tool.execute(params: { action: "destroy_everything" })
        expect(result[:success]).to be false
        expect(result[:error]).to match(/Unknown action/)
      end
    end

    context "parameter validation" do
      it "raises ArgumentError when action is missing" do
        expect { tool.execute(params: {}) }.to raise_error(ArgumentError, /Missing required parameters: action/)
      end
    end
  end
end
