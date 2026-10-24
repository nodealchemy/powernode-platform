# frozen_string_literal: true

require "rails_helper"

# c13-2 batch C-C. One human-only verb (emergency_resume) parks for a person's own session
# whoever calls, and three require_approval verbs (agent_container_terminate,
# code_prune_stale, prune_stale_git_runners) park for an approval. emergency_halt
# is the DELIBERATE exemption: it never parks. Every example asserts the ROW as
# well as the envelope.
RSpec.describe "c13-2 batch C-C destructive verbs park", type: :service do
  include PermissionTestHelpers

  let(:account) { create(:account) }
  let!(:owner) { create(:user, account: account) } # first user: account owner
  let(:person) do
    create(:user, account: account,
                  permissions: %w[ai.autonomy.approve ai.kill_switch.manage ai.agents.read ai.agents.execute])
  end
  let(:manager) do
    create(:user, account: account,
                  permissions: %w[ai.agents.execute ai.knowledge_graph.manage ai.agents.read
                                  git.runners.read git.runners.manage])
  end
  let(:reader) { create(:user, account: account, permissions: %w[ai.agents.read git.runners.read]) }

  after { ::Mcp::Principal.reset! }

  def tool_for(tool_class, user:, agent: nil)
    tool = tool_class.new(account: account, user: user, agent: agent)
    tool.call_origin = "mcp_oauth"
    tool
  end

  def run(tool_class, params, user:, agent: nil)
    tool_for(tool_class, user: user, agent: agent).execute(params: params.with_indifferent_access)
  end

  def workflow = Ai::Autonomy::ApprovalWorkflowService.new(account: account)

  def expect_parked(result, category, human_only:)
    expect(result).to include(success: true)
    expect(result[:data]).to include(pending: true)
    operation = Ai::DeferredOperation.find(result[:data][:deferred_operation_id])
    expect(operation.action_category).to eq(category)
    expect(operation.executor_class).to eq("Ai::Executors::DeferredToolCall")
    request = Ai::ApprovalRequest.find(result[:data][:approval_request_id])
    expect(request.requires_human_session?).to be(true)
    expect(result[:data]).to include(requires_human_session: true) if human_only
    operation
  end

  def confirm!(parked, as: person, expect_ok: true)
    request = Ai::ApprovalRequest.find(parked[:data][:approval_request_id])
    decided = workflow.approve(request: request, approver: as, origin: Ai::ApprovalDecision::REST_SESSION)
    expect(decided).to be(true) if expect_ok
    Ai::DeferredOperation.find(parked[:data][:deferred_operation_id]).reload
  end

  let(:kill_switch) { Ai::Autonomy::KillSwitchService.new(account: account) }

  # Read fresh: a replay works on its own Account instance.
  def halted? = Account.find(account.id).ai_suspended?

  describe "emergency_resume (human_only)" do
    before { kill_switch.emergency_halt!(reason: "spec", triggered_by: owner) }

    it "parks for a person's own session and leaves AI activity halted" do
      parked = run(Ai::Tools::KillSwitchTool, { action: "emergency_resume" }, user: person)

      expect_parked(parked, "ai.kill_switch.resume", human_only: true)
      expect(halted?).to be(true)
    end

    it "refuses an agent principal with no user, and resumes nothing" do
      agent = create(:ai_agent, account: account)

      result = run(Ai::Tools::KillSwitchTool, { action: "emergency_resume" }, user: nil, agent: agent)

      expect(result[:success]).to be(false)
      expect(Ai::DeferredOperation.count).to eq(0)
      expect(halted?).to be(true)
    end

    it "resumes as the person who confirms it in their own session" do
      parked = run(Ai::Tools::KillSwitchTool, { action: "emergency_resume", mode: "minimal" }, user: person)

      operation = confirm!(parked)

      expect(operation.status).to eq("completed")
      expect(halted?).to be(false)
    end

    it "refuses a caller without ai.kill_switch.manage and parks nothing" do
      result = run(Ai::Tools::KillSwitchTool, { action: "emergency_resume" }, user: reader)

      expect(result[:success]).to be(false)
      expect(result[:error]).to match(/permission denied: ai.kill_switch.manage/)
      expect(Ai::DeferredOperation.count).to eq(0)
      expect(halted?).to be(true)
    end

    it "refuses the replay when the confirming person lacks ai.kill_switch.manage" do
      parked = run(Ai::Tools::KillSwitchTool, { action: "emergency_resume" }, user: person)
      approver = create(:user, account: account, permissions: %w[ai.autonomy.approve ai.agents.read ai.agents.execute])

      confirm!(parked, as: approver, expect_ok: false)

      expect(halted?).to be(true)
    end

    it "keeps the human REST path: POST /kill_switch/resume is the controller's own, ungated action" do
      expect(Rails.application.routes.recognize_path("/api/v1/ai/kill_switch/resume", method: :post))
        .to include(controller: "api/v1/ai/kill_switch", action: "resume")
      expect(Api::V1::Ai::KillSwitchController.instance_methods(false)).to include(:resume, :halt)
    end
  end

  describe "approve_deferred_operation / reject_deferred_operation (exempt by decision: the MCP door stays)" do
    %w[approve_deferred_operation reject_deferred_operation].each do |verb|
      it "keeps #{verb} ungated, on the denied list, and named in UNGATED_BY_DECISION" do
        declaration = Ai::Tools::AgentAutonomyTool.declared_action(verb)

        expect(Ai::Tools::AgentAutonomyTool.may_park?(declaration)).to be(false)
        expect(declaration[:human_only]).to be_falsey
        expect(Ai::ClaudeExport::ThinLoader::DENIED_DESTRUCTIVE_ACTIONS).to include(verb)
        expect(Ai::ClaudeExport::ThinLoader::UNGATED_BY_DECISION).to include(verb)
      end
    end
  end

  describe "emergency_halt (the deliberate exemption: never parks)" do
    it "is named as the exemption, stays on the agents' denied list, and is not gate-routed" do
      expect(Ai::ClaudeExport::ThinLoader::UNGATED_BY_DECISION).to include("emergency_halt")
      expect(Ai::ClaudeExport::ThinLoader::DENIED_DESTRUCTIVE_ACTIONS).to include("emergency_halt")
      declaration = Ai::Tools::KillSwitchTool.declared_action("emergency_halt")
      expect(Ai::Tools::KillSwitchTool.may_park?(declaration)).to be(false)
      expect(declaration[:human_only]).to be_falsey
    end

    it "halts AI activity at once for a human session, with no approval parked" do
      result = run(Ai::Tools::KillSwitchTool, { action: "emergency_halt", reason: "spec" }, user: person)

      expect(result[:success]).to be(true)
      expect(Ai::DeferredOperation.count).to eq(0)
      expect(Ai::ApprovalRequest.count).to eq(0)
      expect(halted?).to be(true)
    end
  end

  describe "agent_container_terminate" do
    let(:template) { create(:devops_container_template, account: account) }
    let!(:instance) { create(:devops_container_instance, :paused, account: account, template: template) }

    before do
      allow_any_instance_of(Devops::ContainerOrchestrationService).to receive(:build_gitea_client).and_return(nil)
    end

    it "parks, leaving the container running" do
      expect_any_instance_of(Devops::ContainerOrchestrationService).not_to receive(:cancel)

      parked = run(Ai::Tools::ContainerTerminateTool, { execution_id: instance.execution_id }, user: manager)

      expect_parked(parked, "ai.container.terminate", human_only: false)
      expect(instance.reload.status).to eq("paused")
    end

    it "terminates on approval, as the original caller" do
      parked = run(Ai::Tools::ContainerTerminateTool, { execution_id: instance.execution_id }, user: manager)
      expect_any_instance_of(Devops::ContainerOrchestrationService).to receive(:cancel)
        .with(instance.execution_id, reason: anything).and_return(true)

      operation = confirm!(parked)

      expect(operation.status).to eq("completed")
    end

    it "refuses a caller without ai.agents.execute and parks nothing" do
      result = run(Ai::Tools::ContainerTerminateTool, { execution_id: instance.execution_id }, user: reader)

      expect(result[:success]).to be(false)
      expect(result[:error]).to match(/permission denied: ai.agents.execute/)
      expect(Ai::DeferredOperation.count).to eq(0)
    end
  end

  describe "code_prune_stale (alias of prune_stale)" do
    it "gates the real action and its registry alias" do
      alias_key = "code_prune_stale"
      klass = Ai::Tools::PlatformApiToolRegistry.all_tools.fetch(alias_key).constantize
      action = ToolDeclarationCoverage.resolved_action_name(alias_key, klass)

      expect(action).to eq("prune_stale")
      expect(klass.may_park?(klass.declared_action(action))).to be(true)
    end

    it "parks, enqueueing and writing nothing" do
      parked = run(Ai::Tools::CodeMemoryTool, { action: "prune_stale", repository_id: SecureRandom.uuid, dry_run: false }, user: manager)

      expect_parked(parked, "ai.code_memory.prune", human_only: false)
    end

    it "refuses a caller without ai.knowledge_graph.manage and parks nothing" do
      result = run(Ai::Tools::CodeMemoryTool, { action: "prune_stale", repository_id: SecureRandom.uuid }, user: reader)

      expect(result[:success]).to be(false)
      expect(result[:error]).to match(/permission denied: ai.knowledge_graph.manage/)
      expect(Ai::DeferredOperation.count).to eq(0)
    end
  end

  describe "prune_stale_git_runners" do
    let!(:runner) { create(:git_runner, account: account, name: "fleet-doomed", status: "offline") }

    it "parks even with apply: true, deleting nothing" do
      parked = run(Ai::Tools::GitRunnerInventoryTool, { action: "prune_stale_git_runners", apply: true }, user: manager)

      expect_parked(parked, "ai.git_runner.prune", human_only: false)
      expect(Devops::GitRunner.where(id: runner.id)).to exist
    end

    it "deletes the stale runner on approval, as the original caller" do
      parked = run(Ai::Tools::GitRunnerInventoryTool, { action: "prune_stale_git_runners", apply: true }, user: manager)

      operation = confirm!(parked)

      expect(operation.status).to eq("completed")
      expect(Devops::GitRunner.where(id: runner.id)).not_to exist
    end

    it "refuses the replay, keeping the runner, when git.runners.manage was revoked after parking" do
      parked = run(Ai::Tools::GitRunnerInventoryTool, { action: "prune_stale_git_runners", apply: true }, user: manager)
      RolePermission.where(role_id: manager.roles.select(:id), permission_name: "git.runners.manage").delete_all

      operation = confirm!(parked)

      expect(Devops::GitRunner.where(id: runner.id)).to exist
      expect(operation.reload.result.to_h.to_s).to match(/git\.runners\.manage/)
    end

    it "refuses a caller without git.runners.manage and parks nothing" do
      result = run(Ai::Tools::GitRunnerInventoryTool, { action: "prune_stale_git_runners", apply: true }, user: reader)

      expect(result[:success]).to be(false)
      expect(result[:error]).to match(/git\.runners\.manage/)
      expect(Ai::DeferredOperation.count).to eq(0)
      expect(Devops::GitRunner.where(id: runner.id)).to exist
    end
  end
end
