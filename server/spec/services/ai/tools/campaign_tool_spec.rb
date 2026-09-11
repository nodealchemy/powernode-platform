# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Tools::CampaignTool do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:tool) { described_class.new(account: account, user: user) }

  def exec(params)
    tool.execute(params: params.with_indifferent_access)
  end

  it "registers a campaign permission + declares its actions" do
    expect(described_class::REQUIRED_PERMISSION).to eq("ai.campaigns.manage")
    expect(described_class.action_definitions.keys).to contain_exactly(
      "campaign_propose", "campaign_list_proposals", "campaign_update_proposal", "campaign_approve_proposal",
      "campaign_reject_proposal", "campaign_delegate",
      "campaign_start", "campaign_list", "campaign_status", "campaign_claim", "campaign_release",
      "campaign_answer_question", "campaign_record_increment", "campaign_check_rebase", "campaign_stop",
      "campaign_resume"
    )
  end

  it "campaign_list_proposals returns the deduped proposal queue (filterable by status)" do
    create(:ai_campaign_proposal, account: account, status: "proposed")
    create(:ai_campaign_proposal, :queued, account: account)

    res = exec(action: "campaign_list_proposals")
    expect(res[:success]).to be true
    expect(res[:data][:proposals].size).to eq(2)

    res = exec(action: "campaign_list_proposals", status: "queued")
    expect(res[:data][:proposals].size).to eq(1)
  end

  it "campaign_list returns the account's campaigns" do
    exec(action: "campaign_start", name: "Listable")
    res = exec(action: "campaign_list")
    expect(res[:success]).to be true
    expect(res[:data][:campaigns].map { |c| c[:name] }).to include("Listable")
  end

  it "campaign_delegate routes a campaign loop to a driver (claude_code takes the lease)" do
    id = exec(action: "campaign_start", name: "Routable")[:data][:campaign][:id]

    res = exec(action: "campaign_delegate", campaign_id: id, driver_kind: "claude_code", holder: "sess-x")
    expect(res[:success]).to be true
    expect(res[:data][:driver_kind]).to eq("claude_code")
    expect(res[:data][:lease][:holder]).to eq("sess-x")
    expect(res[:data][:loops].first[:driver_kind]).to eq("claude_code")
  end

  it "campaign_delegate requires a driver_kind and rejects an unknown one" do
    id = exec(action: "campaign_start", name: "Routable2")[:data][:campaign][:id]
    expect(exec(action: "campaign_delegate", campaign_id: id)[:success]).to be false
    expect(exec(action: "campaign_delegate", campaign_id: id, driver_kind: "nope")[:success]).to be false
  end

  it "campaign_propose enqueues a deduped proposal" do
    res = exec(action: "campaign_propose", title: "Add export", objective: "Add CSV export to reports", scope: "core")
    expect(res[:success]).to be true
    expect(res[:data][:proposal][:status]).to eq("proposed")

    # Same target again → refreshed, not duplicated.
    exec(action: "campaign_propose", title: "Add export v2", objective: "Add CSV export to reports", scope: "core")
    expect(account.ai_campaign_proposals.count).to eq(1)
  end

  # Secreview LOW: the verb passed no actor to propose!, so it skipped the shared campaign check.
  it "campaign_propose asks the shared campaign check for its user, creating nothing for one who lacks manage here" do
    user # the account's first user (OWNER) holds ai.campaigns.manage
    reader = create(:user, account: account, permissions: %w[ai.campaigns.read])

    res = described_class.new(account: account, user: reader)
                         .execute(params: { action: "campaign_propose", title: "Reader",
                                            objective: "Not mine to queue" }.with_indifferent_access)
    expect(res[:success]).to be false
    expect(res[:error]).to include("user #{reader.id} does not hold 'ai.campaigns.manage' in account #{account.id}")
    expect(account.ai_campaign_proposals.count).to eq(0)

    res = exec(action: "campaign_propose", title: "Owner", objective: "Mine to queue")
    expect(res[:success]).to be true
    expect(account.ai_campaign_proposals.pluck(:title)).to eq(["Owner"])
  end

  it "campaign_update_proposal revises fields on a proposed proposal and recomputes its fingerprint" do
    pid = exec(action: "campaign_propose", title: "Add export", objective: "Add CSV export to reports", scope: "core")[:data][:proposal][:id]
    original_fingerprint = account.ai_campaign_proposals.find(pid).fingerprint

    res = exec(action: "campaign_update_proposal", proposal_id: pid, title: "Add export v2",
               objective: "Add CSV+JSON export to reports")
    expect(res[:success]).to be true
    expect(res[:data][:proposal][:title]).to eq("Add export v2")

    proposal = account.ai_campaign_proposals.find(pid)
    expect(proposal.objective).to eq("Add CSV+JSON export to reports")
    expect(proposal.fingerprint).not_to eq(original_fingerprint)
  end

  it "campaign_update_proposal errors on an unknown proposal, an empty update, or an already-approved one" do
    expect(exec(action: "campaign_update_proposal", proposal_id: "nope", title: "x")[:success]).to be false

    pid = exec(action: "campaign_propose", title: "Widget", objective: "Build the widget")[:data][:proposal][:id]
    expect(exec(action: "campaign_update_proposal", proposal_id: pid)[:success]).to be false

    exec(action: "campaign_approve_proposal", proposal_id: pid)
    res = exec(action: "campaign_update_proposal", proposal_id: pid, title: "too late")
    expect(res[:success]).to be false
    expect(res[:error]).to match(/spawned proposal/)
  end

  # Secreview LOW: the verb changed a proposal with no shared campaign check at all.
  it "campaign_update_proposal asks the shared campaign check for its user, changing nothing for one who lacks manage here" do
    pid = exec(action: "campaign_propose", title: "Owner's", objective: "Owner objective")[:data][:proposal][:id]
    reader = create(:user, account: account, permissions: %w[ai.campaigns.read])

    res = described_class.new(account: account, user: reader)
                         .execute(params: { action: "campaign_update_proposal", proposal_id: pid,
                                            title: "Rewritten by a reader" }.with_indifferent_access)
    expect(res[:success]).to be false
    expect(res[:error]).to include("user #{reader.id} does not hold 'ai.campaigns.manage' in account #{account.id}")
    expect(account.ai_campaign_proposals.find(pid).title).to eq("Owner's")

    res = exec(action: "campaign_update_proposal", proposal_id: pid, title: "Owner rewrite")
    expect(res[:success]).to be true
    expect(account.ai_campaign_proposals.find(pid).title).to eq("Owner rewrite")
  end

  it "campaign_reject_proposal rejects a proposed/queued proposal with a reason" do
    pid = exec(action: "campaign_propose", title: "Not needed", objective: "Do something unnecessary")[:data][:proposal][:id]

    res = exec(action: "campaign_reject_proposal", proposal_id: pid, reason: "duplicate of existing work")
    expect(res[:success]).to be true
    expect(res[:data][:proposal][:status]).to eq("rejected")

    proposal = account.ai_campaign_proposals.find(pid)
    expect(proposal.rejection_reason).to eq("duplicate of existing work")
    expect(proposal.reviewed_by_id).to eq(user.id)
  end

  it "campaign_reject_proposal errors on an unknown proposal or an already-spawned one" do
    expect(exec(action: "campaign_reject_proposal", proposal_id: "nope")[:success]).to be false

    pid = exec(action: "campaign_propose", title: "Widget2", objective: "Build widget 2")[:data][:proposal][:id]
    exec(action: "campaign_approve_proposal", proposal_id: pid)
    res = exec(action: "campaign_reject_proposal", proposal_id: pid)
    expect(res[:success]).to be false
    expect(res[:error]).to match(/campaign_stop/)
  end

  it "campaign_approve_proposal approves + spawns the campaign in one step (concierge path)" do
    pid = exec(action: "campaign_propose", title: "Build widget", objective: "Build the widget",
               suggested_workload: "feature-development")[:data][:proposal][:id]

    res = exec(action: "campaign_approve_proposal", proposal_id: pid)
    expect(res[:success]).to be true
    expect(res[:data][:campaign][:name]).to eq("Build widget")
    expect(res[:data][:loop][:branch]).to start_with("campaign/")

    proposal = account.ai_campaign_proposals.find(pid)
    expect(proposal.status).to eq("spawned")
    expect(proposal.spawned_campaign_id).to eq(res[:data][:campaign][:id])
  end

  it "campaign_approve_proposal errors on an unknown proposal" do
    expect(exec(action: "campaign_approve_proposal", proposal_id: "nope")[:success]).to be false
  end

  it "campaign_check_rebase advises behind campaigns and returns the advised set" do
    res = exec(action: "campaign_check_rebase", target_branch: "develop")
    expect(res[:success]).to be true
    expect(res[:data][:target_branch]).to eq("develop")
    expect(res[:data]).to have_key(:advised)
  end

  it "campaign_claim takes the single-driver lease and campaign_release frees it" do
    id = exec(action: "campaign_start", name: "X")[:data][:campaign][:id]

    claimed = exec(action: "campaign_claim", campaign_id: id, holder: "sess-a")
    expect(claimed[:success]).to be true
    expect(claimed[:data][:ok]).to be true
    expect(claimed[:data][:lease][:holder]).to eq("sess-a")

    blocked = exec(action: "campaign_claim", campaign_id: id, holder: "sess-b")
    expect(blocked[:data][:ok]).to be false
    expect(blocked[:data][:held_by]).to eq("sess-a")

    released = exec(action: "campaign_release", campaign_id: id, holder: "sess-a")
    expect(released[:data][:ok]).to be true
    expect(exec(action: "campaign_claim", campaign_id: id, holder: "sess-b")[:data][:ok]).to be true
  end

  it "campaign_record_increment records a passed task + decision and reflects completion" do
    id = exec(action: "campaign_start", name: "Obs")[:data][:campaign][:id]
    res = exec(action: "campaign_record_increment", campaign_id: id, title: "Increment 1", summary: "did it")
    expect(res[:success]).to be true
    expect(res[:data][:campaign][:completion_pct]).to eq(100.0)
    expect(res[:data][:status]).to eq("passed")
  end

  it "campaign_record_increment requires a title" do
    id = exec(action: "campaign_start", name: "Obs")[:data][:campaign][:id]
    expect(exec(action: "campaign_record_increment", campaign_id: id)[:success]).to be false
  end

  it "campaign_record_increment passes check_results through to evidence adjudication (IMP-aa8a2f58e01e)" do
    id = exec(action: "campaign_start", name: "Obs")[:data][:campaign][:id]
    exec(action: "campaign_record_increment", campaign_id: id, title: "Evidenced",
         check_results: { "rspec" => "12 examples, 0 failures" })
    iter = Ai::Campaign.find(id).ralph_loops.first.ralph_iterations.last
    expect(iter.checks_passed).to be(true)
    expect(iter.check_results["evidence_verdict"]).to eq("verified")
  end

  it "campaign_start creates a campaign + a campaign-scoped loop" do
    res = exec(action: "campaign_start", name: "Audit billing", decision_authority: "trusted")
    expect(res[:success]).to be true
    expect(res[:data][:campaign][:name]).to eq("Audit billing")
    expect(res[:data][:loop][:branch]).to start_with("campaign/")
  end

  it "campaign_start requires a name" do
    res = exec(action: "campaign_start")
    expect(res[:success]).to be false
  end

  it "campaign_status returns the ledger summary" do
    id = exec(action: "campaign_start", name: "X")[:data][:campaign][:id]
    res = exec(action: "campaign_status", campaign_id: id)
    expect(res[:success]).to be true
    expect(res[:data][:campaign][:name]).to eq("X")
    expect(res[:data][:loops].size).to eq(1)
  end

  it "answers a parked question then stops the campaign" do
    id = exec(action: "campaign_start", name: "X")[:data][:campaign][:id]
    campaign = account.ai_campaigns.find(id)
    q = campaign.park_question!(question: "Pricing policy?")

    ans = exec(action: "campaign_answer_question", campaign_id: id, question_id: q.id, answer: "free 100/mo")
    expect(ans[:success]).to be true
    expect(q.reload.status).to eq("answered")

    stop = exec(action: "campaign_stop", campaign_id: id, summary: "done")
    expect(stop[:success]).to be true
    expect(campaign.reload.status).to eq("completed")
  end

  it "returns an error for an unknown campaign" do
    expect(exec(action: "campaign_status", campaign_id: "nope")[:success]).to be false
  end

  it "campaign_record_increment is a no-op (halted) when the account AI is suspended (kill-switch)" do
    id = exec(action: "campaign_start", name: "Killable")[:data][:campaign][:id]
    account.update!(ai_suspended: true)
    res = exec(action: "campaign_record_increment", campaign_id: id, title: "should not record")
    expect(res[:success]).to be true
    expect(res[:data][:halted]).to be true
    expect(account.ai_campaigns.find(id).campaign_decisions.count).to eq(0)
  end

  describe "campaign_resume" do
    # A campaign that genuinely auto-completed on its stop condition: failed increments
    # against max_failed drive record_increment!'s snapshot + maybe_finalize! to complete
    # it. Built through that real path so the resume runs against the state the finalizer
    # actually leaves behind, not a hand-set status.
    def auto_completed_campaign(name: "Resumable", max_failed: 2)
      id = exec(action: "campaign_start", name: name, stop_conditions: { max_failed: max_failed })[:data][:campaign][:id]
      max_failed.times do |i|
        exec(action: "campaign_record_increment", campaign_id: id, title: "broken #{i}", status: "failed")
      end
      campaign = account.ai_campaigns.find(id)
      expect(campaign.status).to eq("completed") # precondition: the stop condition finalized it
      expect(campaign.failed_tasks).to eq(max_failed)
      campaign
    end

    it "resumes an auto-completed campaign with a raised cap, and it stays active across the next snapshot" do
      campaign = auto_completed_campaign

      res = exec(action: "campaign_resume", campaign_id: campaign.id, stop_conditions: { max_failed: 6 },
                 reason: "two known-flaky failures; raise the cap")
      expect(res[:success]).to be(true), res[:error].to_s
      expect(res[:data][:campaign][:status]).to eq("active")
      expect(campaign.reload.status).to eq("active")
      # MERGED, not replaced: the start-time default survives beside the raised cap.
      expect(campaign.stop_conditions).to eq("min_acceptance_pct" => 50, "max_failed" => 6)
      expect(campaign.completed_at).to be_nil

      # The next increment snapshots progress and runs maybe_finalize! — the very path
      # that completed it. With the cap raised it must not flip back.
      exec(action: "campaign_record_increment", campaign_id: campaign.id, title: "fixed", status: "passed")
      expect(campaign.reload.status).to eq("active")
      expect(campaign.failed_tasks).to eq(2)
    end

    it "refuses, by name, a resume whose merged stop conditions would re-complete it, leaving it untouched" do
      campaign = auto_completed_campaign
      decisions_before = campaign.campaign_decisions.count

      res = exec(action: "campaign_resume", campaign_id: campaign.id, reason: "just try again")
      expect(res[:success]).to be false
      expect(res[:error]).to match(/stop condition 'max_failed'/)
      expect(campaign.reload.status).to eq("completed")

      # A merge that still trips is refused the same way, and the merge is rolled back.
      res = exec(action: "campaign_resume", campaign_id: campaign.id, stop_conditions: { max_failed: 1 },
                 reason: "lower cap")
      expect(res[:success]).to be false
      expect(res[:error]).to match(/stop condition 'max_failed'/)
      expect(campaign.reload.status).to eq("completed")
      expect(campaign.stop_conditions).to eq("min_acceptance_pct" => 50, "max_failed" => 2)
      expect(campaign.campaign_decisions.count).to eq(decisions_before)
    end

    it "refuses an archived campaign by name" do
      archived = create(:ai_campaign, account: account, status: "archived")

      res = exec(action: "campaign_resume", campaign_id: archived.id, reason: "bring it back")
      expect(res[:success]).to be false
      expect(res[:error]).to match(/is archived/)
      expect(archived.reload.status).to eq("archived")
      expect(archived.campaign_decisions.count).to eq(0)
    end

    it "refuses an already-active campaign by name" do
      active = create(:ai_campaign, :active, account: account, stop_conditions: { "max_failed" => 3 })

      res = exec(action: "campaign_resume", campaign_id: active.id, stop_conditions: { max_failed: 9 }, reason: "x")
      expect(res[:success]).to be false
      expect(res[:error]).to match(/is already active/)
      expect(active.reload.stop_conditions).to eq("max_failed" => 3)
      expect(active.campaign_decisions.count).to eq(0)
    end

    it "requires a reason and a known campaign" do
      campaign = auto_completed_campaign

      res = exec(action: "campaign_resume", campaign_id: campaign.id, stop_conditions: { max_failed: 6 })
      expect(res[:success]).to be false
      expect(res[:error]).to match(/reason is required/)
      expect(campaign.reload.status).to eq("completed")

      expect(exec(action: "campaign_resume", campaign_id: "nope", reason: "x")[:error]).to eq("Campaign not found")
    end

    it "records the resume as a campaign decision with the actor, reason, and old and new stop conditions" do
      campaign = auto_completed_campaign
      campaign.update_column(:last_activity_at, 1.day.ago)

      res = exec(action: "campaign_resume", campaign_id: campaign.id,
                 stop_conditions: { max_failed: 6, completion_pct: 90 }, reason: "raise the cap")
      expect(res[:success]).to be(true), res[:error].to_s

      decision = campaign.campaign_decisions.find(res[:data][:decision_id])
      expect(decision.decision_type).to eq("policy")
      expect(decision.rationale).to eq("raise the cap")
      expect(decision.user_id).to eq(user.id)
      expect(decision.metadata).to include(
        "action" => "campaign_resume",
        "principal" => "user",
        "previous_status" => "completed",
        "old_stop_conditions" => { "min_acceptance_pct" => 50, "max_failed" => 2 },
        "new_stop_conditions" => { "min_acceptance_pct" => 50, "max_failed" => 6, "completion_pct" => 90 }
      )
      expect(campaign.reload.last_activity_at).to be_within(1.minute).of(Time.current)
    end

    it "is a no-op (halted) when the account AI is suspended (kill-switch)" do
      campaign = auto_completed_campaign
      account.update!(ai_suspended: true)

      res = exec(action: "campaign_resume", campaign_id: campaign.id, stop_conditions: { max_failed: 6 }, reason: "x")
      expect(res[:data][:halted]).to be true
      expect(campaign.reload.status).to eq("completed")
    end

    # Security review §9 fix 1: a null reads as "no such stop", so a merged nil used to
    # slip past the re-complete guard AND delete the stop. Every value must be a valid
    # value of its key's type; nothing is removed.
    it "refuses, by name, a stop value that is null, a string, the wrong type, inert or unknown, deleting nothing" do
      campaign = auto_completed_campaign
      before_conditions = campaign.stop_conditions.dup

      {
        { max_failed: nil } => "max_failed",
        { max_failed: 9, min_acceptance_pct: nil } => "min_acceptance_pct",
        { max_failed: "6" } => "max_failed",
        { max_failed: 6.5 } => "max_failed",
        { max_failed: 0 } => "max_failed",
        { max_failed: true } => "max_failed",
        { max_failed: 9, min_acceptance_pct: 0 } => "min_acceptance_pct",
        { max_failed: 9, completion_pct: 101 } => "completion_pct",
        { max_failed: 9, min_acceptance_sample: "4" } => "min_acceptance_sample",
        { max_failed: 9, max_cost_per_accepted_change: 0 } => "max_cost_per_accepted_change",
        { max_failed: 9, no_such_stop: 3 } => "no_such_stop"
      }.each do |conditions, key|
        res = exec(action: "campaign_resume", campaign_id: campaign.id, stop_conditions: conditions, reason: "probe")
        expect(res[:success]).to be(false), "#{conditions.inspect} was accepted"
        expect(res[:error]).to include("invalid stop condition").and include("'#{key}'")
      end
      expect(campaign.reload.status).to eq("completed")
      expect(campaign.stop_conditions).to eq(before_conditions)
    end

    it "accepts a valid value of each stop condition's type and stores it as given" do
      campaign = auto_completed_campaign
      conditions = { max_failed: 6, min_acceptance_sample: 8, completion_pct: 95.5, min_acceptance_pct: 40,
                     max_cost_per_accepted_change: 2.5 }

      res = exec(action: "campaign_resume", campaign_id: campaign.id, stop_conditions: conditions, reason: "retune")
      expect(res[:success]).to be(true), res[:error].to_s
      expect(campaign.reload.stop_conditions).to eq(conditions.stringify_keys)
      expect(campaign.stop_conditions["max_failed"]).to be_a(Integer)
    end

    # §9 fix 3: the campaign's own driver cannot re-arm it.
    it "refuses while a driver holds the campaign's lease, and goes through once the lease is released" do
      campaign = auto_completed_campaign
      exec(action: "campaign_claim", campaign_id: campaign.id, holder: "driver-loop-1")

      res = exec(action: "campaign_resume", campaign_id: campaign.id, stop_conditions: { max_failed: 50 },
                 reason: "self re-arm")
      expect(res[:success]).to be false
      expect(res[:error]).to include("held by driver 'driver-loop-1'")
      expect(campaign.reload.status).to eq("completed")
      expect(campaign.stop_conditions["max_failed"]).to eq(2)

      exec(action: "campaign_release", campaign_id: campaign.id, holder: "driver-loop-1")
      res = exec(action: "campaign_resume", campaign_id: campaign.id, stop_conditions: { max_failed: 50 },
                 reason: "operator, after the driver let go")
      expect(res[:success]).to be(true), res[:error].to_s
      expect(campaign.reload.status).to eq("active")
    end

    # §9 fix 4: the driver itself never writes a resume that names no one.
    it "has the driver refuse a resume with no acting user, before any write" do
      campaign = auto_completed_campaign
      nobody_driver = Ai::DevLoop::CampaignDriver.new(account: account, user: nil)

      expect { nobody_driver.resume(campaign, reason: "no one", stop_conditions: { max_failed: 6 }) }
        .to raise_error(ArgumentError, /acting user/)
      expect(campaign.reload.status).to eq("completed")
      expect(campaign.campaign_decisions.where("metadata->>'action' = ?", "campaign_resume")).to be_empty
    end

    # Re-review E11: the permission lives in the shared service, so every door (the MCP
    # verb, the REST action, any later caller) inherits it; a door-only check is how a
    # future caller skips it.
    it "has the driver refuse a user without ai.campaigns.manage, called directly, before any write" do
      campaign = auto_completed_campaign
      reader = create(:user, account: account, permissions: %w[ai.campaigns.read])
      reader_driver = Ai::DevLoop::CampaignDriver.new(account: account, user: reader)

      expect { reader_driver.resume(campaign, reason: "not mine to make", stop_conditions: { max_failed: 6 }) }
        .to raise_error(Ai::Campaigns::Authorization::Refused, /user #{reader.id} does not hold 'ai\.campaigns\.manage'/)
      expect(campaign.reload.status).to eq("completed")
      expect(campaign.stop_conditions["max_failed"]).to eq(2)
      expect(campaign.campaign_decisions.where("metadata->>'action' = ?", "campaign_resume")).to be_empty
    end

    # §9 fix 2: a resume is a human operator's decision. Authority an agent or an
    # instance inherits from the account is not consent (the A6 H1 ruling).
    describe "principals" do
      let(:campaign) { auto_completed_campaign }

      def resume_as(tool_instance)
        tool_instance.execute(params: { action: "campaign_resume", campaign_id: campaign.id,
                                        stop_conditions: { max_failed: 50 }, reason: "re-arm" }.with_indifferent_access)
      end

      def expect_refused_untouched(res, named)
        expect(res[:success]).to be false
        expect(res[:error]).to match(named)
        expect(campaign.reload.status).to eq("completed")
        expect(campaign.stop_conditions["max_failed"]).to eq(2)
        expect(campaign.campaign_decisions.where("metadata->>'action' = ?", "campaign_resume")).to be_empty
      end

      it "refuses an agent acting beside a creator who holds ai.campaigns.manage" do
        agent = create(:ai_agent, account: account, creator: user)
        expect_refused_untouched(resume_as(described_class.new(account: account, user: user, agent: agent)),
                                 /human operator's decision.*agent #{agent.id}/)
      end

      it "refuses an agent alone whose creator is powerless, though the account owner holds the permission" do
        campaign # built by the owner before the powerless user exists (the first user becomes OWNER)
        powerless = create(:user, account: account, permissions: [])
        agent = create(:ai_agent, account: account, creator: powerless)
        expect_refused_untouched(resume_as(described_class.new(account: account, agent: agent)),
                                 /human operator's decision.*agent #{agent.id}/)
      end

      it "refuses a grant-gated instance principal" do
        instance_tool = described_class.new(account: account)
        instance_tool.instance_authorized = true
        expect_refused_untouched(resume_as(instance_tool), /human operator's decision.*instance principal/)
      end

      it "refuses an internal caller with no user" do
        expect_refused_untouched(resume_as(described_class.new(account: account, internal: true)),
                                 /human operator's decision.*no user/)
      end

      it "refuses a user who does not personally hold ai.campaigns.manage, even constructed past the registrar" do
        campaign # built by the owner before the restricted user exists
        reader = create(:user, account: account, permissions: %w[ai.campaigns.read])
        expect_refused_untouched(resume_as(described_class.new(account: account, user: reader)),
                                 /does not hold 'ai\.campaigns\.manage'/)
      end

      it "lets the human operator who holds the permission through (positive control)" do
        res = resume_as(described_class.new(account: account, user: user))
        expect(res[:success]).to be(true), res[:error].to_s
        expect(campaign.reload.status).to eq("active")
      end
    end
  end

  # The gate is the tool's REQUIRED_PERMISSION, enforced by the registrar before the
  # tool is constructed — the same floor campaign_stop sits behind. Exercised through
  # McpPlatformToolRegistrar.execute_tool, the seam MCP callers actually pass.
  describe "campaign_resume authorization" do
    let(:completed) { create(:ai_campaign, account: account, status: "completed", stop_conditions: {}) }

    # The first user created in an account is given the OWNER role (spec/factories/users.rb),
    # so occupy that slot before creating the restricted principals.
    before { user }

    def via_mcp(tool_name, params, as:)
      ::Ai::Tools::McpPlatformToolRegistrar.execute_tool(
        "platform.#{tool_name}", params: params, account: account, user: as
      )
    rescue ::Mcp::ProtocolService::PermissionDeniedError => e
      { success: false, error: e.message, denied: true }
    end

    it "denies every principal that cannot stop a campaign, exactly as campaign_stop does" do
      nobody = create(:user, account: account, permissions: [])
      reader = create(:user, account: account, permissions: %w[ai.campaigns.read])

      [nobody, reader].each do |principal|
        stop = via_mcp("campaign_stop", { campaign_id: completed.id }, as: principal)
        resume = via_mcp("campaign_resume", { campaign_id: completed.id, reason: "x" }, as: principal)
        expect(stop[:denied]).to be(true)
        expect(resume[:denied]).to be(true)
        expect(resume[:error]).to include("requires 'ai.campaigns.manage'")
      end
      expect(completed.reload.status).to eq("completed")
      expect(completed.campaign_decisions.count).to eq(0)
    end

    it "lets a principal holding ai.campaigns.manage through to the resume" do
      manager = create(:user, account: account, permissions: %w[ai.campaigns.manage])

      res = via_mcp("campaign_resume", { campaign_id: completed.id, reason: "operator resume" }, as: manager)
      expect(res[:success]).to be(true), res[:error].to_s
      expect(completed.reload.status).to eq("active")
      expect(completed.campaign_decisions.last.user_id).to eq(manager.id)
    end

    it "refuses an MCP call that carries an agent, though the token's user holds ai.campaigns.manage" do
      agent = create(:ai_agent, account: account, creator: user)

      res = ::Ai::Tools::McpPlatformToolRegistrar.execute_tool(
        "platform.campaign_resume", params: { campaign_id: completed.id, reason: "agent via mcp" },
                                    account: account, user: user, mcp_agent: agent
      )
      expect(res[:success]).to be false
      expect(res[:error]).to match(/human operator's decision/)
      expect(completed.reload.status).to eq("completed")
      expect(completed.campaign_decisions.count).to eq(0)
    end
  end
end
