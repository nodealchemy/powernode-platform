# frozen_string_literal: true

require "rails_helper"

# IMP-6fbfeff384fa — per-ACTION authorization parity for the five core MCP tool
# classes that still inherited BaseTool's REQUIRED_PERMISSION = nil.
#
# McpPlatformToolRegistrar#enforce_permission! opens with `return if
# required.nil?` — ABOVE the authentication raise, the has_permission? raise and
# the MCP token intersection. So every action on ProvisioningTool,
# SelfImprovementTool, GovernanceTool, CoordinationTool and
# AgentMemoryManagementTool was reachable with no check at all. This is the same
# shape that made AgentAutonomyTool a live authorization bypass
# (IMP-e8adfcfcab9b), and the fix is the same seam: a FLOOR constant the
# registrar enforces for the whole class, plus an ACTION_PERMISSIONS map the
# tool enforces against the action that actually RUNS.
#
# The invariant is parity per ACTION: nothing reachable over MCP may be more
# permissive than the REST surface for the same operation. One constant per tool
# cannot express that — each of these bundles reads with writes — so a single
# permissive constant would look gated while leaving the sensitive actions open.
#
# Two failure modes are covered deliberately, because a refusal-only suite sees
# neither:
#   * under-gating — the "smuggled action" examples are the sharp end: a user
#     principal is NOT pinned to the invoked tool name
#     (McpPlatformToolRegistrar#action_pinned_to_name?), so a name-keyed check is
#     bypassable by supplying a sibling :action;
#   * over-gating — the positive examples pass on unmodified HEAD (where nothing
#     is gated) and exist solely to catch a floor that locks legitimate callers
#     out of the benign actions.
RSpec.describe "sibling MCP tools: per-action authorization parity" do
  let(:account) { create(:account) }
  let(:agent) { create(:ai_agent, account: account) }

  # The first user created in an account is given the OWNER role, so every actor
  # declares its permissions explicitly (spec/factories/users.rb).
  let(:nobody) { create(:user, account: account, permissions: []) }

  def run(tool_name, params = {}, user:, mcp_agent: nil)
    ::Ai::Tools::McpPlatformToolRegistrar.execute_tool(
      "platform.#{tool_name}",
      params: params,
      account: account,
      user: user,
      mcp_agent: mcp_agent
    )
  end

  # A refusal is a refusal whether it surfaces as an error result from the tool
  # or as a raise from the registrar. Normalizing both keeps the acceptance
  # criterion on the OBSERVABLE — the operation did not run — rather than on the
  # layer the gate happens to live in.
  def refuse(tool_name, params = {}, user:, mcp_agent: nil)
    run(tool_name, params, user: user, mcp_agent: mcp_agent)
  rescue ::Mcp::ProtocolService::PermissionDeniedError => e
    { success: false, error: e.message }
  end

  # "Got past the gate" without needing the action to succeed: the permission
  # refusal and the domain error are distinguishable, which is what separates
  # "gated" from "broken".
  def expect_past_the_gate(result)
    expect(result[:error].to_s).not_to match(/permission denied/i)
    expect(result[:error].to_s).not_to match(/requires '/)
  end

  describe "Ai::Tools::ProvisioningTool" do
    # REST twins: missions#show gates on ai.missions.read; #create, #compose_plan,
    # #approve and #reject on ai.missions.manage (missions_controller.rb:9-15).
    let(:reader) { create(:user, account: account, permissions: %w[ai.missions.read]) }
    let(:manager) { create(:user, account: account, permissions: %w[ai.missions.read ai.missions.manage]) }

    # Without these two, "creates no mission" is a TAUTOLOGY: unseeded,
    # create_infrastructure_mission! raises "Mission template not seeded" before
    # writing anything, so the count assertion holds whether or not the gate
    # exists. Seeded and stubbed, an ungated capture_brief really does create a
    # mission — which is what makes the row oracle able to fail.
    let!(:provisioning_template) do
      ::Ai::MissionTemplate.find_or_create_by!(
        name: ::Ai::Tools::ProvisioningTool::MISSION_TEMPLATE_NAME, template_type: "system"
      ) do |t|
        t.account = nil
        t.description = "test fixture"
        t.mission_type = "infrastructure"
        t.status = "active"
        t.is_default = true
        t.version = 1
        t.phases = [{ "key" => "capture_intent", "name" => "Capture intent", "order" => 1 }]
      end
    end

    before do
      allow_any_instance_of(::Ai::Provisioning::IntentCaptureService)
        .to receive(:capture).and_return(brief: { "use_case" => "x" }, missing_fields: [:use_case])
    end

    # The two assertions are deliberately NOT nested inside the change block: an
    # expectation that fails inside it aborts before the matcher runs, which
    # would leave the row oracle shadowed by the string oracle.
    it "refuses capture_brief without ai.missions.manage and creates no mission" do
      result = nil

      expect {
        result = refuse(
          "platform_provisioning_capture_brief",
          { "natural_language" => "give me a vm" },
          user: reader
        )
      }.not_to change { ::Ai::Mission.where(account_id: account.id).count }

      expect(result[:success]).to be(false)
      expect(result[:error]).to include("ai.missions.manage")
    end

    # The premise of the two row oracles above and below: with the gate removed,
    # this same call DOES write a mission. Without this control they would be
    # satisfied by any unrelated failure.
    it "writes a mission when the caller does hold ai.missions.manage (premise)" do
      expect {
        result = run(
          "platform_provisioning_capture_brief",
          { "natural_language" => "give me a vm" },
          user: manager
        )
        expect(result[:success]).to be(true)
      }.to change { ::Ai::Mission.where(account_id: account.id).count }.by(1)
    end

    it "refuses adapt, which dispatches a live infrastructure change" do
      result = refuse(
        "platform_provisioning_adapt",
        { "mission_id" => SecureRandom.uuid, "change_type" => "scale_up" },
        user: reader
      )

      expect(result[:success]).to be(false)
      expect(result[:error]).to include("ai.missions.manage")
    end

    # A user principal is deliberately unpinned from the invoked name, so the
    # gate has to key on the action that RUNS.
    it "refuses an approve smuggled in under the read-only status name" do
      result = nil

      expect {
        result = refuse(
          "platform_provisioning_status",
          { "action" => "platform_provisioning_capture_brief", "natural_language" => "vm" },
          user: reader
        )
      }.not_to change { ::Ai::Mission.where(account_id: account.id).count }

      expect(result[:success]).to be(false)
      expect(result[:error]).to include("ai.missions.manage")
    end

    it "refuses a caller holding no permissions at the floor" do
      expect {
        run("platform_provisioning_status", { "mission_id" => SecureRandom.uuid }, user: nobody)
      }.to raise_error(::Mcp::ProtocolService::PermissionDeniedError, /ai\.missions\.read/)
    end

    it "refuses a call carrying no user at all" do
      expect {
        run("platform_provisioning_status", { "mission_id" => SecureRandom.uuid }, user: nil)
      }.to raise_error(::Mcp::ProtocolService::PermissionDeniedError, /Authentication required/)
    end

    # CONTROLS — green on unmodified HEAD; they guard against over-tightening.
    it "keeps the status read usable at the floor" do
      result = run("platform_provisioning_status", { "mission_id" => SecureRandom.uuid }, user: reader)

      expect(result[:success]).to be(false)
      expect(result[:error]).to match(/not found/i)
      expect_past_the_gate(result)
    end

    it "still composes for a caller holding ai.missions.manage" do
      result = run("platform_provisioning_compose_plan", { "mission_id" => SecureRandom.uuid }, user: manager)

      expect(result[:error]).to match(/not found/i)
      expect_past_the_gate(result)
    end
  end

  describe "Ai::Tools::SelfImprovementTool" do
    # REST twins: the self-challenge surface is gated as a family on ai.manage
    # (agent_intelligence_controller.rb:76-81); skill writes on
    # ai.skills.update / ai.skills.create (skills_controller.rb).
    let(:reader) { create(:user, account: account, permissions: %w[ai.skills.read]) }
    let(:updater) { create(:user, account: account, permissions: %w[ai.skills.read ai.skills.update]) }
    let(:creator) { create(:user, account: account, permissions: %w[ai.skills.read ai.skills.create]) }
    let(:ai_manager) { create(:user, account: account, permissions: %w[ai.skills.read ai.manage]) }
    let!(:skill) { create(:ai_skill, account: account) }

    # The oracle is that the mutation service is never CONSTRUCTED. A row count
    # would be vacuous here: SkillMutationService#mutate! returns nil before
    # writing when the skill has no matching learnings, and #compose_skills!
    # returns nil for fewer than two components — so "no version written" and
    # "no skill written" hold against a no-op gate too.
    it "refuses mutate_skill without ai.skills.update and never reaches the mutation service" do
      expect(::Ai::SelfImprovement::SkillMutationService).not_to receive(:new)

      result = refuse(
        "mutate_skill",
        { "skill_id" => skill.id, "strategy" => "learning_driven" },
        user: reader, mcp_agent: agent
      )

      expect(result[:success]).to be(false)
      expect(result[:error]).to include("ai.skills.update")
    end

    it "refuses compose_skills without ai.skills.create and never reaches the mutation service" do
      expect(::Ai::SelfImprovement::SkillMutationService).not_to receive(:new)

      result = refuse(
        "compose_skills",
        { "component_skill_ids" => [skill.id], "name" => "composite" },
        user: reader, mcp_agent: agent
      )

      expect(result[:success]).to be(false)
      expect(result[:error]).to include("ai.skills.create")
    end

    it "refuses auto_evolve_skill, which mutates every underperforming skill" do
      expect(::Ai::SelfImprovement::SkillMutationService).not_to receive(:new)

      result = refuse("auto_evolve_skill", { "threshold" => 0.9 }, user: reader, mcp_agent: agent)

      expect(result[:success]).to be(false)
      expect(result[:error]).to include("ai.skills.update")
    end

    it "refuses the self-challenge reads without ai.manage" do
      result = refuse("list_challenges", {}, user: reader, mcp_agent: agent)

      expect(result[:success]).to be(false)
      expect(result[:error]).to include("ai.manage")
    end

    it "refuses a skill mutation smuggled in under the challenge-list name" do
      expect(::Ai::SelfImprovement::SkillMutationService).not_to receive(:new)

      result = refuse(
        "list_challenges",
        { "action" => "mutate_skill", "skill_id" => skill.id, "strategy" => "learning_driven" },
        user: ai_manager, mcp_agent: agent
      )

      expect(result[:success]).to be(false)
      expect(result[:error]).to include("ai.skills.update")
    end

    # CONTROLS.
    it "still lists challenges for a caller holding ai.manage" do
      result = run("list_challenges", {}, user: ai_manager, mcp_agent: agent)

      expect(result[:success]).to be(true)
      expect(result[:data][:count]).to eq(0)
    end

    it "still mutates for a caller holding ai.skills.update" do
      result = run("mutate_skill", { "skill_id" => SecureRandom.uuid, "strategy" => "learning_driven" },
                   user: updater, mcp_agent: agent)

      expect(result[:error]).to match(/not found/i)
      expect_past_the_gate(result)
    end

    it "still composes for a caller holding ai.skills.create" do
      result = run("compose_skills", { "component_skill_ids" => [], "name" => "composite" },
                   user: creator, mcp_agent: agent)

      expect_past_the_gate(result)
    end
  end

  describe "Ai::Tools::GovernanceTool" do
    # REST twin: governance_reports_controller.rb:13-14 — reads on
    # ai.governance.read, resolve on ai.governance.manage.
    let(:reader) { create(:user, account: account, permissions: %w[ai.governance.read]) }
    let(:manager) { create(:user, account: account, permissions: %w[ai.governance.read ai.governance.manage]) }
    let!(:report) do
      ::Ai::GovernanceReport.create!(
        account: account, subject_agent: agent,
        report_type: "anomaly", severity: "warning", status: "open",
        evidence: { "seed" => true }
      )
    end

    it "refuses resolve_governance_report without ai.governance.manage (the reported hole)" do
      result = refuse(
        "resolve_governance_report",
        { "report_id" => report.id, "resolution_status" => "dismissed" },
        user: reader
      )

      expect(result[:success]).to be(false)
      expect(result[:error]).to include("ai.governance.manage")
      expect(report.reload.status).to eq("open")
    end

    # Again the oracle is non-construction of the service. Counting rows would be
    # vacuous: MonitorService writes a report only when a violation/abuse/anomaly
    # predicate trips, and an indicator only above COLLUSION_THRESHOLD, none of
    # which a pair of fresh factory agents reaches.
    it "refuses governance_scan, which writes governance records" do
      expect(::Ai::Governance::MonitorService).not_to receive(:new)

      result = refuse("governance_scan", { "agent_id" => agent.id }, user: reader)

      expect(result[:success]).to be(false)
      expect(result[:error]).to include("ai.governance.manage")
    end

    it "refuses detect_collusion, which writes collusion indicators" do
      expect(::Ai::Governance::MonitorService).not_to receive(:new)

      result = refuse("detect_collusion", {}, user: reader)

      expect(result[:success]).to be(false)
      expect(result[:error]).to include("ai.governance.manage")
    end

    it "refuses a resolve smuggled in under the report-list name" do
      result = refuse(
        "list_governance_reports",
        { "action" => "resolve_governance_report", "report_id" => report.id, "resolution_status" => "dismissed" },
        user: reader
      )

      expect(result[:success]).to be(false)
      expect(result[:error]).to include("ai.governance.manage")
      expect(report.reload.status).to eq("open")
    end

    # CONTROLS.
    it "keeps the report reads usable at the floor" do
      listed = run("list_governance_reports", {}, user: reader)
      expect(listed[:success]).to be(true)
      expect(listed[:data][:reports].map { |r| r["id"] }).to include(report.id)

      fetched = run("get_governance_report", { "report_id" => report.id }, user: reader)
      expect(fetched[:success]).to be(true)

      dashboard = run("governance_dashboard", {}, user: reader)
      expect(dashboard[:success]).to be(true)
    end

    it "still resolves for a caller holding ai.governance.manage" do
      result = run(
        "resolve_governance_report",
        { "report_id" => report.id, "resolution_status" => "dismissed" },
        user: manager
      )

      expect(result[:success]).to be(true)
      expect(report.reload.status).to eq("dismissed")
    end
  end

  describe "Ai::Tools::CoordinationTool" do
    # REST twins: the coordination dashboard reads gate on ai.manage
    # (coordination_dashboard_controller.rb:92); agent_teams#add_member and
    # #optimize on ai.teams.manage (agent_teams_controller.rb:21,237).
    let(:reader) { create(:user, account: account, permissions: %w[ai.agents.read]) }
    let(:perceiver) { create(:user, account: account, permissions: %w[ai.agents.read ai.manage]) }
    let(:team_manager) { create(:user, account: account, permissions: %w[ai.agents.read ai.teams.manage]) }
    let!(:team) { create(:ai_agent_team, account: account) }
    let!(:recruitable) { create(:ai_agent, account: account, status: "active") }
    let(:recruit_params) { { "team_id" => team.id, "capability" => "ruby" } }

    # Non-construction again: recruit_member! raises before team.members.create!
    # (see the note on the positive control below), so a membership count cannot
    # tell a refusal apart from that raise.
    it "refuses recruit_agent without ai.teams.manage and never reaches the team service" do
      expect(::Ai::Coordination::SelfOrganizingTeamService).not_to receive(:new)

      result = refuse("recruit_agent", recruit_params, user: reader, mcp_agent: agent)

      expect(result[:success]).to be(false)
      expect(result[:error]).to include("ai.teams.manage")
    end

    it "refuses measure_pressure, which returns the same field the dashboard read serves" do
      expect(::Ai::Coordination::PressureFieldService).not_to receive(:new)

      result = refuse(
        "measure_pressure",
        { "artifact_ref" => "spec/artifact", "artifact_type" => "file", "field_type" => "complexity" },
        user: reader, mcp_agent: agent
      )

      expect(result[:success]).to be(false)
      expect(result[:error]).to include("ai.manage")
    end

    # "No restructure events" would be satisfied by an empty team either way, so
    # the oracle is that the service is never CONSTRUCTED — the operation did
    # not run, not merely that it happened to write nothing.
    it "refuses optimize_team, which rewrites team composition" do
      expect(::Ai::Coordination::SelfOrganizingTeamService).not_to receive(:new)

      result = refuse("optimize_team", { "team_id" => team.id }, user: reader, mcp_agent: agent)

      expect(result[:success]).to be(false)
      expect(result[:error]).to include("ai.teams.manage")
    end

    it "refuses the coordination reads without ai.manage" do
      signals = refuse("perceive_signals", {}, user: reader, mcp_agent: agent)
      expect(signals[:success]).to be(false)
      expect(signals[:error]).to include("ai.manage")

      pressure = refuse("perceive_pressure", {}, user: reader, mcp_agent: agent)
      expect(pressure[:success]).to be(false)
      expect(pressure[:error]).to include("ai.manage")
    end

    it "refuses a recruit smuggled in under the emit_signal name" do
      expect(::Ai::Coordination::SelfOrganizingTeamService).not_to receive(:new)

      result = refuse(
        "emit_signal",
        recruit_params.merge("action" => "recruit_agent"),
        user: reader, mcp_agent: agent
      )

      expect(result[:success]).to be(false)
      expect(result[:error]).to include("ai.teams.manage")
    end

    # CONTROLS. emit/reinforce/measure have NO REST twin and are an agent's own
    # coordination voice, so they stay at the floor deliberately — pinned so a
    # later tightening is a deliberate act rather than a side effect.
    it "keeps signal emission usable at the floor" do
      result = run(
        "emit_signal",
        { "signal_type" => "pheromone", "signal_key" => "spec.trail" },
        user: reader, mcp_agent: agent
      )

      expect(result[:success]).to be(true)
      expect(::Ai::StigmergicSignal.where(account_id: account.id, signal_key: "spec.trail")).to exist
    end

    it "still perceives for a caller holding ai.manage" do
      result = run("perceive_signals", {}, user: perceiver, mcp_agent: agent)

      expect(result[:success]).to be(true)
    end

    it "still optimizes for a caller holding ai.teams.manage" do
      result = run("optimize_team", { "team_id" => team.id }, user: team_manager, mcp_agent: agent)

      expect(result[:success]).to be(true)
    end

    # recruit_agent cannot be shown SUCCEEDING here, and that is not this
    # change's doing: Ai::Agent has no `capabilities` attribute (it lives in
    # metadata), so SelfOrganizingTeamService#recruit_member! raises
    # PG::UndefinedColumn on `Ai::Agent.where("capabilities @> ?", ...)` for any
    # capability, and fails the member's own capabilities validation without
    # one. Reproduced on unmodified HEAD and filed separately. The oracle that
    # remains available is the one that matters here — a permitted caller gets
    # PAST the gate and fails downstream, which is what separates "gated" from
    # "locked out".
    it "still reaches recruitment for a caller holding ai.teams.manage" do
      result = run("recruit_agent", recruit_params, user: team_manager, mcp_agent: agent)

      expect(result[:success]).to be(false)
      expect_past_the_gate(result)
      expect(result[:error]).to match(/capabilities/i)
    end
  end

  describe "Ai::Tools::AgentMemoryManagementTool" do
    # All four actions are structurally self-scoped: no action takes an agent or
    # pool parameter, and the pool is derived from the CALLING agent identity
    # (AgentManagedMemoryService#find_private_pool), which an MCP caller cannot
    # choose. So there is one decision for the whole class, not four — the floor
    # matches the sibling MemoryTool, which gates the same Ai::MemoryPool model.
    let(:reader) { create(:user, account: account, permissions: %w[ai.agents.read]) }

    it "refuses a caller holding no permissions at all" do
      expect {
        run("agent_remember", { "key" => "k", "value" => "v" }, user: nobody, mcp_agent: agent)
      }.to raise_error(::Mcp::ProtocolService::PermissionDeniedError, /ai\.agents\.read/)
    end

    it "refuses a call carrying no user at all" do
      expect {
        run("agent_forget", { "key" => "k" }, user: nil, mcp_agent: agent)
      }.to raise_error(::Mcp::ProtocolService::PermissionDeniedError, /Authentication required/)
    end

    it "refuses a token that does not grant the floor" do
      token = ::UserToken.new(permissions: %w[ai.conversations.read])
      allow(token).to receive(:has_permission?).with("ai.agents.read").and_return(false)

      expect {
        ::Ai::Tools::McpPlatformToolRegistrar.execute_tool(
          "platform.agent_remember",
          params: { "key" => "k", "value" => "v" },
          account: account, user: reader, mcp_agent: agent, token: token
        )
      }.to raise_error(::Mcp::ProtocolService::PermissionDeniedError, /Token does not grant/)
    end

    # CONTROL — an agent's own memory must stay usable at member tier.
    it "keeps the agent's own memory operations usable at the floor" do
      remembered = run("agent_remember", { "key" => "spec.key", "value" => "v" }, user: reader, mcp_agent: agent)
      expect(remembered[:success]).to be(true)

      recalled = run("agent_recall", { "query" => "spec" }, user: reader, mcp_agent: agent)
      expect(recalled[:success]).to be(true)
    end
  end

  # Both bypass arms of action_permitted? are load-bearing and neither is
  # observable from the examples above: without these, deleting
  # `return true if instance_authorized?` or `return true if internal?` from all
  # four maps reds nothing.
  describe "the two explicit bypasses" do
    let!(:report) do
      ::Ai::GovernanceReport.create!(
        account: account, subject_agent: agent,
        report_type: "anomaly", severity: "warning", status: "open", evidence: {}
      )
    end

    # An mTLS node principal carries no User, so has_permission? has nothing to
    # ask about. Its authorization is the name-scoped grant the streamable
    # controller already checked, which enforce_permission! honours above the
    # has_permission? raise and action_permitted? honours in turn. Without this
    # arm every such call is hard-denied — the regression BUG-R recorded.
    it "still serves an instance principal, whose grant is name-scoped" do
      result = ::Ai::Tools::McpPlatformToolRegistrar.execute_tool(
        "platform.resolve_governance_report",
        params: { "report_id" => report.id, "resolution_status" => "dismissed" },
        account: account, user: nil, instance_authorized: true
      )

      expect(result[:success]).to be(true)
      expect(report.reload.status).to eq("dismissed")
    end

    # ...and the grant is still the bound: the registrar pins an instance's
    # action to the name it invoked, so the smuggling route stays shut for the
    # principal whose per-action check is deliberately waived.
    it "refuses an instance principal an action it did not invoke by name" do
      expect {
        ::Ai::Tools::McpPlatformToolRegistrar.execute_tool(
          "platform.list_governance_reports",
          params: { "action" => "resolve_governance_report", "report_id" => report.id,
                    "resolution_status" => "dismissed" },
          account: account, user: nil, instance_authorized: true
        )
      }.to raise_error(::Mcp::ProtocolService::PermissionDeniedError, /not permitted/)

      expect(report.reload.status).to eq("open")
    end

    # `internal: true` is the in-process system caller's opt-in. It is never
    # reachable through the registrar (which does not pass it), so it is driven
    # by direct construction — the shape reconcilers and skill executors use.
    it "waives the per-action check for an explicit internal caller" do
      result = ::Ai::Tools::GovernanceTool.new(account: account, user: nil, internal: true)
        .execute(params: { "action" => "resolve_governance_report", "report_id" => report.id,
                           "resolution_status" => "confirmed" }.with_indifferent_access)

      expect(result[:success]).to be(true)
      expect(report.reload.status).to eq("confirmed")
    end

    # ...and a nil user WITHOUT that opt-in is refused, which is the distinction
    # IMP-9030413bc292 exists to hold: "no user" must never imply "internal".
    it "refuses a nil-user caller that did not declare itself internal" do
      result = ::Ai::Tools::GovernanceTool.new(account: account, user: nil)
        .execute(params: { "action" => "resolve_governance_report", "report_id" => report.id,
                           "resolution_status" => "confirmed" }.with_indifferent_access)

      expect(result[:success]).to be(false)
      expect(result[:error]).to include("ai.governance.manage")
      expect(report.reload.status).to eq("open")
    end
  end

  describe "the constants themselves" do
    it "no longer waves any of the five through enforce_permission!" do
      {
        ::Ai::Tools::ProvisioningTool => "ai.missions.read",
        ::Ai::Tools::SelfImprovementTool => "ai.skills.read",
        ::Ai::Tools::GovernanceTool => "ai.governance.read",
        ::Ai::Tools::CoordinationTool => "ai.agents.read",
        ::Ai::Tools::AgentMemoryManagementTool => "ai.agents.read"
      }.each do |tool_class, floor|
        expect(tool_class::REQUIRED_PERMISSION).to eq(floor), "expected #{tool_class} floor to be #{floor}"
      end
    end

    it "pins each privileged action to the permission its REST twin requires" do
      expect(::Ai::Tools::ProvisioningTool::ACTION_PERMISSIONS).to eq(
        "platform_provisioning_capture_brief" => "ai.missions.manage",
        "platform_provisioning_compose_plan" => "ai.missions.manage",
        "platform_provisioning_approve_plan" => "ai.missions.manage",
        "platform_provisioning_adapt" => "ai.missions.manage"
      )

      expect(::Ai::Tools::SelfImprovementTool::ACTION_PERMISSIONS).to eq(
        "generate_self_challenge" => "ai.manage",
        "list_challenges" => "ai.manage",
        "get_challenge_result" => "ai.manage",
        "mutate_skill" => "ai.skills.update",
        "auto_evolve_skill" => "ai.skills.update",
        "compose_skills" => "ai.skills.create"
      )

      expect(::Ai::Tools::GovernanceTool::ACTION_PERMISSIONS).to eq(
        "governance_scan" => "ai.governance.manage",
        "detect_collusion" => "ai.governance.manage",
        "resolve_governance_report" => "ai.governance.manage"
      )

      expect(::Ai::Tools::CoordinationTool::ACTION_PERMISSIONS).to eq(
        "perceive_signals" => "ai.manage",
        "perceive_pressure" => "ai.manage",
        "measure_pressure" => "ai.manage",
        "optimize_team" => "ai.teams.manage",
        "recruit_agent" => "ai.teams.manage"
      )
    end

    it "maps only actions these tools actually serve" do
      [
        ::Ai::Tools::ProvisioningTool,
        ::Ai::Tools::SelfImprovementTool,
        ::Ai::Tools::GovernanceTool,
        ::Ai::Tools::CoordinationTool
      ].each do |tool_class|
        unknown = tool_class::ACTION_PERMISSIONS.keys - tool_class.action_definitions.keys
        expect(unknown).to be_empty, "#{tool_class} maps actions it does not serve: #{unknown.join(', ')}"
      end
    end

    # AgentMemoryManagementTool deliberately carries NO map: all four of its
    # actions are the same self-scoped operation on the caller's own pool, so
    # splitting them would invent a distinction the surface does not have.
    it "leaves the self-scoped memory tool without a per-action map" do
      expect(::Ai::Tools::AgentMemoryManagementTool.const_defined?(:ACTION_PERMISSIONS, false)).to be(false)
    end

    # Its floor is the sibling MCP surface's bar for the same Ai::MemoryPool
    # model, read from that class rather than restated so drift is a failure.
    it "keeps the memory floor equal to the sibling shared-memory tool's" do
      expect(::Ai::Tools::AgentMemoryManagementTool::REQUIRED_PERMISSION)
        .to eq(::Ai::Tools::MemoryTool::REQUIRED_PERMISSION)
    end
  end
end
