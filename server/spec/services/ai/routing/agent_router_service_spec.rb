# frozen_string_literal: true

require "rails_helper"

# HIER-P1B item 10 — ONE router for both sides. The candidate set is the same
# routable set the Claude Code exporter emits (Ai::Routing::RoutableAgents), it
# honours the delegator's Ai::DelegationPolicy, and it names the CC
# `subagent_type` slug for the winner so an MCP caller can Agent() it directly.
RSpec.describe Ai::Routing::AgentRouterService do
  let(:account) { create(:account) }
  let(:provider) { create(:ai_provider, account: account, provider_type: "openai", is_active: true) }
  subject(:router) { described_class.new(account: account) }

  def agent(name:, description:, agent_type: "assistant", **attrs)
    create(:ai_agent, account: account, provider: provider, name: name, description: description,
                      agent_type: agent_type, status: "active", **attrs)
  end

  describe "#route candidate set" do
    it "routes over the routable set: the account's active agents plus the GLOBAL canonicals" do
      own = agent(name: "Fleet Reconciler", description: "Reconciles fleet drift and module upgrades.")
      canonical = create(:ai_agent, :global, is_system: true, name: "Canonical Drift Fixer",
                         description: "Reconciles fleet drift and module upgrades on every node.")
      create(:ai_agent, :mcp_client, account: account) # never routable
      create(:ai_agent, :inactive, account: account, name: "Paused", description: "Reconciles fleet drift.")
      create(:ai_agent, account: create(:account), name: "Foreign", description: "Reconciles fleet drift.")

      result = router.route(task: "reconcile fleet drift and upgrade modules")
      ids = result[:candidates].map { |c| c[:agent_id] }

      expect(ids).to include(own.id, canonical.id)
      expect(ids.size).to eq(2)
    end

    # HIER-P2I: routing MAY return a global canonical — it is the template the
    # account has not cloned yet — but a canonical never executes (ruling 8).
    # The result says so, per candidate and for the winner, so the CALLER
    # clones (Ai::Agents::AccountPrincipalResolver) before executing instead
    # of meeting the tool seam's refusal.
    it "flags a global canonical winner and candidate so the caller clones before executing" do
      canonical = create(:ai_agent, :global, is_system: true, name: "Canonical Drift Fixer",
                         description: "Reconciles fleet drift and module upgrades on every node.")

      result = router.route(task: "reconcile fleet drift and upgrade modules")

      expect(result[:agent_id]).to eq(canonical.id)
      expect(result[:canonical]).to be(true)
      expect(result[:execution_note]).to match(/clone/i)
      expect(result[:candidates].find { |c| c[:agent_id] == canonical.id }[:canonical]).to be(true)
    end

    it "does not flag an account-owned winner" do
      own = agent(name: "Fleet Reconciler", description: "Reconciles fleet drift and module upgrades.")

      result = router.route(task: "reconcile fleet drift and upgrade modules")

      expect(result[:agent_id]).to eq(own.id)
      expect(result[:canonical]).to be(false)
      expect(result).not_to have_key(:execution_note)
      expect(result[:candidates].first[:canonical]).to be(false)
    end

    it "does not raise on an agent without a capabilities column (declared_capabilities is the live definition)" do
      agent(name: "Any", description: "Anything at all.")

      expect { router.route(task: "do anything") }.not_to raise_error
    end

    # EQUALITY ORACLE: the router composes declared_capabilities from its batched
    # skills instead of re-plucking per candidate. If either side changes, this
    # fails rather than the router quietly matching on a different vocabulary.
    it "composes exactly what Ai::Agent#declared_capabilities returns" do
      subject_agent = agent(name: "Composed", description: "Anything.",
                            mcp_metadata: { "capabilities" => %w[quarantine drain] })
      active_skill = create(:ai_skill, account: account, slug: "reap-instance", status: "active")
      stale_skill = create(:ai_skill, account: account, slug: "retired-skill", status: "active")
      create(:ai_agent_skill, agent: subject_agent, skill: active_skill, is_active: true)
      create(:ai_agent_skill, agent: subject_agent, skill: stale_skill, is_active: false)

      composed = router.send(:declared_capabilities_for, subject_agent,
                             router.send(:skills_by_agent, [ subject_agent.id ])[subject_agent.id] || [])

      expect(composed.sort).to eq(subject_agent.declared_capabilities.sort)
      expect(composed).to include("reap-instance")
      expect(composed).not_to include("retired-skill")
    end

    # HIER-P2G — the skill dimension profiles a canonical agent by the skills
    # the ROUTING ACCOUNT can see (GloballyScopable.for_account: global rows +
    # its own), never by another tenant's private skill bound to the shared
    # canonical row. Before the system skills were global, the router saw
    # Account.first's rows from every account, and saw nothing once they were
    # converted — either way the wrong profile.
    it "profiles a canonical agent by its GLOBAL skills and the routing account's own, never another tenant's" do
      canonical = create(:ai_agent, :global, name: "Canonical Router Target", description: "Generic.", is_system: true)
      global_skill = create(:ai_skill, :global, slug: "system-quarantine-node", name: "Quarantine Node",
                                                description: "Quarantines a node.")
      own_skill = create(:ai_skill, account: account, slug: "own-triage", name: "Own Triage", description: "Triage.")
      foreign = create(:ai_skill, account: create(:account), slug: "foreign-zebra", name: "Foreign Zebra",
                                  description: "Zebra handling.")
      [ global_skill, own_skill, foreign ].each { |skill| create(:ai_agent_skill, agent: canonical, skill: skill, is_active: true) }

      profile = router.send(:skills_by_agent, [ canonical.id ])[canonical.id].map(&:slug)
      expect(profile).to eq(%w[own-triage system-quarantine-node])

      result = router.route(task: "quarantine the zebra node")
      target = result[:candidates].find { |c| c[:agent_id] == canonical.id }
      expect(target[:reasons][:skill]).to include("quarantine")
      expect(target[:reasons][:skill]).not_to include("zebra")
    end

    it "consumes declared_capabilities in the skill dimension (not merely surviving its absence)" do
      matcher = agent(name: "Alpha", description: "Generic.",
                      mcp_metadata: { "capabilities" => %w[quarantine] })
      plain = agent(name: "Beta", description: "Generic.")
      allow_any_instance_of(Ai::Agent).to receive(:declared_capabilities).and_wrap_original do |orig, *args|
        orig.call(*args)
      end

      result = router.route(task: "quarantine the affected node")
      matched = result[:candidates].find { |c| c[:agent_id] == matcher.id }
      unmatched = result[:candidates].find { |c| c[:agent_id] == plain.id }

      expect(matched[:reasons][:skill]).to include("quarantine")
      expect(unmatched[:reasons][:skill]).to eq("no task-term overlap with the agent's profile or skills")
    end
  end

  # CLAUDE.md eager-loading rule: #score runs once per candidate, so anything it
  # reads per candidate multiplies. Every relation it needs (skills, trust
  # scores, the execution window, policy domains) is batched for the whole pool
  # in #build_context BEFORE the loop.
  describe "query budget" do
    it "does not grow its query count per additional candidate" do
      5.times { |i| agent(name: "Agent #{i}", description: "Reconciles fleet drift number #{i}.") }
      task = "reconcile fleet drift"
      router.route(task: task) # warm the schema/constant caches

      small = count_queries { described_class.new(account: account).route(task: task) }
      15.times { |i| agent(name: "Extra #{i}", description: "Reconciles fleet drift extra #{i}.") }
      large = count_queries { described_class.new(account: account).route(task: task) }

      expect(large).to be <= small + 2
    end

    def count_queries(&block)
      count = 0
      counter = ->(*, payload) { count += 1 unless payload[:name].to_s =~ /SCHEMA|TRANSACTION/ }
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
      count
    end
  end

  describe "#route result shape" do
    it "names the winner's CC subagent_type slug and gives every candidate a reason per dimension" do
      winner = agent(name: "SDWAN Manager", description: "Manages SD-WAN peers, route policies and overlays.",
                     agent_type: "monitor")
      agent(name: "CVE Responder", description: "Triages CVEs and plans critical upgrades.", agent_type: "monitor")

      result = router.route(task: "create an sdwan peer and update the route policies for the overlay")

      expect(result[:agent_id]).to eq(winner.id)
      expect(result[:subagent_type]).to eq(winner.slug)
      expect(result[:candidates].first[:slug]).to eq(winner.slug)
      result[:candidates].each do |candidate|
        expect(candidate[:reasons].keys).to include(:capability, :domain, :tier, :cost, :trust)
        expect(candidate[:score]).to be_a(Numeric)
      end
    end

    it "scores the domain dimension from the agent's intervention-policy domains" do
      sdwan = agent(name: "Net Agent", description: "Generic.", agent_type: "monitor")
      Ai::InterventionPolicy.create!(account: account, agent: sdwan, scope: "agent",
                                     action_category: "system.sdwan_create_peer", policy: "require_approval", priority: 10)
      other = agent(name: "Other Agent", description: "Generic.", agent_type: "monitor")

      result = router.route(task: "sdwan peer attach")
      by_id = result[:candidates].index_by { |c| c[:agent_id] }

      expect(by_id[sdwan.id][:reasons][:domain]).to include("sdwan")
      expect(by_id[sdwan.id][:breakdown][:domain]).to be > by_id[other.id][:breakdown][:domain]
    end

    it "returns the no-agent envelope with a reason when nothing is routable" do
      result = router.route(task: "anything")

      expect(result[:agent_id]).to be_nil
      expect(result[:subagent_type]).to be_nil
      expect(result[:reasoning][:error]).to be_present
    end
  end

  describe "#route honours the delegator's delegation policy" do
    it "excludes the delegator itself and any type its policy does not allow" do
      concierge = agent(name: "Concierge", description: "Operator chat: sdwan peers, route policies, everything.")
      monitor = agent(name: "SDWAN Monitor", description: "sdwan peers and route policies.", agent_type: "monitor")
      assistant = agent(name: "SDWAN Assistant", description: "sdwan peers and route policies.")
      create(:ai_delegation_policy, account: account, agent: concierge, allowed_delegate_types: %w[monitor])

      result = router.route(task: "sdwan peers route policies", delegator: concierge)
      ids = result[:candidates].map { |c| c[:agent_id] }

      expect(ids).to eq([ monitor.id ])
      expect(ids).not_to include(concierge.id, assistant.id)
      expect(result[:delegation]).to include(policy_applied: true, allowed_delegate_types: %w[monitor])
    end

    it "returns the no-agent envelope when the policy excludes every candidate" do
      concierge = agent(name: "Concierge", description: "chat")
      agent(name: "Assistant Only", description: "chat")
      create(:ai_delegation_policy, account: account, agent: concierge, allowed_delegate_types: %w[monitor])

      result = router.route(task: "chat", delegator: concierge)

      expect(result[:agent_id]).to be_nil
      expect(result[:reasoning][:error]).to include("delegation policy")
    end
  end

  # The same task description yields the same winner via the MCP verb and via
  # the Concierge's delegation path (Ai::ConciergeRouter), because both call
  # THIS router over the same candidate set with the same delegator.
  describe "parity with the Concierge delegation path" do
    let(:user) { create(:user, account: account, permissions: %w[ai.agents.read]) }
    let(:concierge) { agent(name: "System Concierge", description: "Operator chat for the system surface.") }
    let(:conversation) do
      create(:ai_conversation, account: account, user: user, agent: concierge, provider: provider, status: "active")
    end
    let(:task) { "provision an sdwan overlay network with route policies for the new peers" }
    let!(:specialist) do
      agent(name: "SDWAN Provisioner", description: "Provisions sdwan overlay networks, route policies and peers.")
    end
    let!(:bystander) do
      agent(name: "Disk Image Curator", description: "Curates disk images and boot publications.")
    end
    let(:entry_skill) do
      create(:ai_skill, account: account, slug: "system-provision-sdwan", name: "Provision SDWAN Overlay",
             category: "devops", status: "active",
             metadata: { "domain" => "system", "invocation_mode" => "workflow_step", "entry_point" => true })
    end

    before do
      create(:ai_agent_skill, agent: specialist, skill: entry_skill, is_active: true)
      create(:ai_agent_skill, agent: bystander, skill: entry_skill, is_active: true)
    end

    it "picks the same winner through ConciergeRouter and through platform.route_task" do
      concierge_router = Ai::ConciergeRouter.new(conversation: conversation, user_message: Struct.new(:body).new(task))
      allow(concierge_router).to receive(:discover_relevant_skills).and_return([ entry_skill ])
      concierge_result = concierge_router.route
      expect(concierge_result.mode).to eq(:delegated)

      tool = Ai::Tools::AgentRoutingTool.new(account: account, user: user)
      mcp_result = tool.execute(params: { action: "route_task", task_description: task,
                                          constraints: { "delegator_agent_id" => concierge.id } })

      expect(mcp_result[:success]).to be true
      expect(concierge_result.delegated_agent.id).to eq(specialist.id)
      expect(mcp_result[:data][:winner][:agent_id]).to eq(concierge_result.delegated_agent.id)
      expect(mcp_result[:data][:subagent_type]).to eq(specialist.slug)
    end

    it "passes the concierge through as the delegator so its delegation policy binds the Concierge path too" do
      create(:ai_delegation_policy, account: account, agent: concierge, allowed_delegate_types: %w[monitor])
      concierge_router = Ai::ConciergeRouter.new(conversation: conversation, user_message: Struct.new(:body).new(task))
      allow(concierge_router).to receive(:discover_relevant_skills).and_return([ entry_skill ])

      expect(concierge_router.route.mode).to eq(:passthrough)
    end
  end
end
