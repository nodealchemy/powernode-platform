# frozen_string_literal: true

require "rails_helper"

# HIER-P2B-ENG — the Platform Developer is the platform_agent driver of
# dev-improve (operator ruling 2026-09-03 #4: it drives the loop as a
# platform_agent alongside Claude Code).
#
# Three properties, each pinned here:
#   1. `campaign_delegate driver_kind: platform_agent` with NO agent named
#      resolves to the Platform Developer — the account's OWN row for the
#      canonical, cloned from the global one on first use (HIER-P1's canonical
#      rule) — and wires that clone onto the loop as default_agent. The global
#      canonical itself is never wired on: the bridge executes a loop's agent
#      as `agent.creator`, which for a canonical is a user in the seeding
#      account.
#   2. That agent can then claim work through dev_next_task under its OWN
#      identity ("agent:<id>"), while every other caller still meets the
#      "delegated_to_platform" halt — the single-driver rule is kept, the
#      delegated driver is simply the one it names.
#   3. With no Platform Developer present, an empty target still raises
#      (no wedged loop) — the default is a resolution, not a bypass.
RSpec.describe Ai::Tools::DevLoopTool, "Platform Developer as the platform_agent driver (HIER-P2B-ENG)" do
  let(:account) { create(:account) }
  let(:user)    { create(:user, account: account) }
  let(:seeding_account) { create(:account, name: "Powernode Admin") }
  let(:seeding_admin) { create(:user, account: seeding_account) }
  let(:cdriver) { Ai::DevLoop::CampaignDriver.new(account: account, user: user) }
  let(:campaign) { cdriver.start(name: "Drainable")[:campaign] }
  let(:loop_record) { campaign.ralph_loops.first }

  # The seeded canonical carries a CREATOR (ai_engineering_agents_seed.rb sets
  # one), and Ai::AgentToolBridgeService — the only path that runs a loop's
  # agent through a platform tool — passes that creator as `user` on every
  # call. The specs below therefore build the tool the way PRODUCTION builds
  # it, `user:` and all; a tool constructed with `agent:` alone is a shape no
  # caller produces.
  def platform_developer!(**attrs)
    create(:ai_agent, :global, name: "Platform Developer", slug: "platform-developer",
                               agent_type: "code_assistant", source_key: "platform-developer",
                               is_system: true, creator: seeding_admin, **attrs)
  end

  # The canonical's creator lives in the SEEDING account, not in the account
  # driving the loop — the shape the bridge hands the tool.
  def bridge_tool(for_agent)
    described_class.new(account: account, user: for_agent.creator, agent: for_agent)
  end

  def pull(tool, holder: nil)
    params = { action: "dev_next_task", loop_id: loop_record.id }
    params[:holder] = holder if holder
    tool.execute(params: params.with_indifferent_access)
  end

  before do
    loop_record.ralph_tasks.create!(task_key: "eng-1", description: "first", status: "pending", priority: 1)
  end

  describe "campaign_delegate with no agent named" do
    it "clones the Platform Developer canonical into the account and wires the CLONE as default agent" do
      canonical = platform_developer!

      result = cdriver.delegate(campaign, driver_kind: "platform_agent", target: {})

      clone = Ai::Agent.find(result[:target]["agent_id"])
      expect(clone.id).not_to eq(canonical.id)
      expect(clone.account_id).to eq(account.id)
      expect(clone.cloned_from_id).to eq(canonical.id)
      # The acting principal the bridge will use belongs to THIS account, not
      # to the seeding account the canonical's creator lives in.
      expect(clone.creator&.account_id).to eq(account.id)
      expect(canonical.creator.account_id).to eq(seeding_account.id)
      expect(loop_record.reload.driver_kind).to eq("platform_agent")
      expect(loop_record.default_agent_id).to eq(clone.id)
      expect(loop_record.scheduling_mode).to eq("continuous")
    end

    it "reuses the account's clone on a second delegation rather than minting another" do
      platform_developer!

      first  = cdriver.delegate(campaign, driver_kind: "platform_agent", target: {})
      second = cdriver.delegate(campaign, driver_kind: "platform_agent", target: {})

      expect(second[:target]).to eq(first[:target])
      expect(account.ai_agents.where(source_key: "platform-developer").count).to eq(1)
    end

    it "refuses the GLOBAL canonical even when named explicitly — a loop runs its own account's row" do
      canonical = platform_developer!

      expect { cdriver.delegate(campaign, driver_kind: "platform_agent", target: { agent_id: canonical.id }) }
        .to raise_error(ArgumentError, /agent not found in this account/)
    end

    it "prefers the account's existing row for the canonical over minting a new clone" do
      canonical = platform_developer!
      existing = create(:ai_agent, account: account, name: "Platform Developer", slug: "platform-developer",
                                   agent_type: "code_assistant", source_key: "platform-developer",
                                   cloned_from: canonical, creator: user)

      result = cdriver.delegate(campaign, driver_kind: "platform_agent", target: {})

      expect(result[:target]).to eq({ "agent_id" => existing.id })
    end

    it "still raises with no Platform Developer present — a default is a resolution, not a wedged loop" do
      expect { cdriver.delegate(campaign, driver_kind: "platform_agent", target: {}) }
        .to raise_error(ArgumentError, /requires target.agent_id/)
      expect(loop_record.reload.driver_kind).not_to eq("platform_agent")
    end

    it "still refuses another account's agent even when named explicitly" do
      foreign = create(:ai_agent, account: create(:account))

      expect { cdriver.delegate(campaign, driver_kind: "platform_agent", target: { agent_id: foreign.id }) }
        .to raise_error(ArgumentError, /agent not found in this account/)
    end
  end

  describe "claiming through dev_next_task under the delegated identity" do
    let!(:canonical) { platform_developer! }
    # What the delegation actually wires on: the account's clone of the canonical.
    let(:driving_agent) { loop_record.reload.default_agent }

    before { cdriver.delegate(campaign, driver_kind: "platform_agent", target: {}) }

    it "lets the delegated Platform Developer claim the task as agent:<id>" do
      # Built exactly as Ai::AgentToolBridgeService builds it — agent AND the
      # agent's creator as `user`. Keying the predicate on `user.nil?` would
      # make this red, which is the point: that shape never occurs in
      # production, so the delegation would be inert.
      tool = bridge_tool(driving_agent)

      result = pull(tool)

      expect(result[:halted]).to be_falsey, "halted: #{result[:reason].inspect}"
      expect(result[:task]).to be_present
      expect(result[:task][:task_key]).to eq("eng-1")
      task = loop_record.ralph_tasks.find_by(task_key: "eng-1")
      expect(task.status).to eq("in_progress")
      # The claim is scoped to the AGENT, not to the creator the bridge passed
      # as `user` — otherwise the identity that claimed and the identity that
      # completes would differ across two tool instances.
      expect(task.metadata["claimed_by"]).to eq("agent:#{driving_agent.id}")
    end

    # The claim scope must be a pure function of the PRINCIPAL: claim, reclaim
    # and complete are separate tool instances, so a claimant_ref that answered
    # "user:<creator>" on one call and "agent:<id>" on another would strand the
    # claim. A second pull by the same principal must RECLAIM, not hand out new
    # work or trip the concurrency cap.
    it "reclaims its own in-flight task on a LATER call (claim and reclaim are separate tools)" do
      loop_record.ralph_tasks.create!(task_key: "eng-2", description: "second", status: "pending", priority: 0)

      first  = pull(bridge_tool(driving_agent))
      second = pull(bridge_tool(driving_agent))

      expect(first[:task][:task_key]).to eq("eng-1")
      expect(second[:halted]).to be_falsey, "halted: #{second[:reason].inspect}"
      expect(second[:task][:task_key]).to eq("eng-1")
      expect(second[:reclaimed]).to be(true)
    end

    it "closes the task it claimed on a later call, through the same identity" do
      pull(bridge_tool(driving_agent))

      result = bridge_tool(driving_agent).execute(
        params: { action: "dev_complete_task", loop_id: loop_record.id, task_key: "eng-1",
                  outcome: "passed", summary: "done" }.with_indifferent_access
      )

      expect(result[:success]).to be(true), "complete failed: #{result[:error].inspect}"
      expect(loop_record.ralph_tasks.find_by(task_key: "eng-1").status).to eq("passed")
    end

    it "still halts a Claude Code session with delegated_to_platform" do
      result = pull(described_class.new(account: account, user: user), holder: "cc-1")

      expect(result[:halted]).to be(true)
      expect(result[:reason]).to eq("delegated_to_platform")
    end

    it "still halts a DIFFERENT platform agent — the delegation names one driver" do
      other = create(:ai_agent, account: account, name: "Someone Else", creator: user)

      result = pull(bridge_tool(other))

      expect(result[:halted]).to be(true)
      expect(result[:reason]).to eq("delegated_to_platform")
    end
  end
end
