# frozen_string_literal: true

require "rails_helper"

# c13-2 batch C-B. Eight destroy-shaped agent, team, skill, ralph-loop and
# data-source verbs were declared `destructive: true` but armed no gate. Each now
# parks behind the autonomy gate as a require_approval deferred tool call and runs
# only on the replay of an approval, as the ORIGINAL caller, with the tool's own
# permission and canonical guards re-run first. Every example asserts the ROW as
# well as the envelope.
RSpec.describe "c13-2 batch C-B destructive verbs park", type: :service do
  let(:account) { create(:account) }
  let!(:owner) { create(:user, account: account) } # first user: account owner
  let(:caller_user) do
    create(:user, account: account,
                  permissions: %w[ai.agents.delete ai.agents.execute ai.skills.update ai.skills.delete
                                  ai.loops.delete ai.data_sources.delete ai.data_sources.stream
                                  ai.agents.update ai.skills.read ai.data_sources.read])
  end
  let(:reader) { create(:user, account: account, permissions: %w[ai.agents.read ai.skills.read]) }

  after { ::Mcp::Principal.reset! }

  def tool_for(tool_class, user: caller_user)
    tool = tool_class.new(account: account, user: user)
    tool.call_origin = "mcp_oauth"
    tool
  end

  def run(tool_class, params = {}, user: caller_user, **rest)
    tool_for(tool_class, user: user).execute(params: params.merge(rest).with_indifferent_access)
  end

  def expect_parked(result, category)
    expect(result).to include(success: true)
    expect(result[:data]).to include(pending: true)
    operation = Ai::DeferredOperation.find(result[:data][:deferred_operation_id])
    expect(operation.action_category).to eq(category)
    expect(operation.executor_class).to eq("Ai::Executors::DeferredToolCall")
    # destructive: true makes the approver a person in their own session, though the
    # verbs are plain require_approval and not human_only.
    expect(Ai::ApprovalRequest.find(result[:data][:approval_request_id]).requires_human_session?).to be(true)
    operation
  end

  def approve!(parked_result, as: owner)
    request = Ai::ApprovalRequest.find(parked_result[:data][:approval_request_id])
    Ai::Autonomy::ApprovalWorkflowService.new(account: account)
                                         .approve(request: request, approver: as,
                                                  origin: Ai::ApprovalDecision::REST_SESSION)
    Ai::DeferredOperation.find(parked_result[:data][:deferred_operation_id])
  end

  describe "parking" do
    it "parks delete_agent, leaving the agent in place" do
      agent = create(:ai_agent, account: account)

      expect_parked(run(Ai::Tools::AgentManagementTool, action: "delete_agent", agent_id: agent.id), "ai.agent.delete")
      expect(Ai::Agent.where(id: agent.id)).to exist
    end

    it "parks delete_team, leaving the team in place" do
      team = create(:ai_agent_team, account: account)

      expect_parked(run(Ai::Tools::TeamManagementTool, action: "delete_team", team_id: team.id), "ai.team.delete")
      expect(Ai::AgentTeam.where(id: team.id)).to exist
    end

    it "parks remove_team_member, leaving the member in place" do
      team = create(:ai_agent_team, account: account)
      member = create(:ai_agent_team_member, team: team, agent: create(:ai_agent, account: account))

      expect_parked(run(Ai::Tools::TeamManagementTool, action: "remove_team_member",
                                                        team_id: team.id, agent_id: member.agent.id),
                    "ai.team.member_remove")
      expect(Ai::AgentTeamMember.where(id: member.id)).to exist
    end

    it "parks delete_skill, leaving the skill in place" do
      skill = create(:ai_skill, account: account)

      expect_parked(run(Ai::Tools::SkillTool, action: "delete_skill", skill_id: skill.id), "ai.skill.delete")
      expect(Ai::Skill.where(id: skill.id)).to exist
    end

    it "parks detach_skill_from_agent, leaving the binding in place" do
      agent = create(:ai_agent, account: account)
      skill = create(:ai_skill, account: account)
      binding = Ai::AgentSkill.create!(agent: agent, skill: skill, is_active: true, priority: 0)

      expect_parked(run(Ai::Tools::SkillTool, action: "detach_skill_from_agent",
                                              skill_id: skill.id, agent_id: agent.id),
                    "ai.skill.detach")
      expect(Ai::AgentSkill.where(id: binding.id)).to exist
    end

    it "parks delete_ralph_loop, leaving the loop in place" do
      loop_record = create(:ai_ralph_loop, account: account)

      expect_parked(run(Ai::Tools::RalphLoopTool, action: "delete_ralph_loop", loop_id: loop_record.id),
                    "ai.ralph_loop.delete")
      expect(Ai::RalphLoop.where(id: loop_record.id)).to exist
    end

    it "parks data_source_delete, leaving the source in place" do
      source = create(:ai_data_source, account: account)

      expect_parked(run(Ai::Tools::DataSourceTool, action: "data_source_delete", data_source_id: source.id),
                    "ai.data_source.delete")
      expect(Ai::DataSource.where(id: source.id)).to exist
    end

    it "parks data_source_unsubscribe, leaving the subscription in place" do
      source = create(:ai_data_source, account: account)
      endpoint = create(:ai_data_source_endpoint, data_source: source)
      subscription = create(:ai_data_source_subscription, data_source: source, endpoint: endpoint)

      expect_parked(run(Ai::Tools::DataSourceTool, action: "data_source_unsubscribe", subscription_id: subscription.id),
                    "ai.data_source.unsubscribe")
      expect(Ai::DataSourceSubscription.where(id: subscription.id)).to exist
    end
  end

  describe "a caller without the action's permission parks nothing" do
    [
      [ Ai::Tools::AgentManagementTool, "delete_agent", { agent_id: "x" } ],
      [ Ai::Tools::SkillTool, "delete_skill", { skill_id: "x" } ],
      [ Ai::Tools::SkillTool, "detach_skill_from_agent", { skill_id: "x", agent_id: "y" } ],
      [ Ai::Tools::RalphLoopTool, "delete_ralph_loop", { loop_id: "x" } ],
      [ Ai::Tools::DataSourceTool, "data_source_unsubscribe", { subscription_id: "x" } ]
    ].each do |tool_class, action, extra|
      it "is refused #{action}" do
        result = run(tool_class, { action: action }.merge(extra), user: reader)

        expect(result[:success]).to be(false)
        expect(Ai::DeferredOperation.count).to eq(0)
        expect(Ai::ApprovalRequest.count).to eq(0)
      end
    end

    it "refuses data_source_delete for a door user without the grant (no agent to file a proposal for)" do
      source = create(:ai_data_source, account: account)

      result = run(Ai::Tools::DataSourceTool, { action: "data_source_delete", data_source_id: source.id }, user: reader)

      expect(result[:success]).to be(false)
      expect(Ai::DeferredOperation.count).to eq(0)
      expect(Ai::DataSource.where(id: source.id)).to exist
    end
  end

  describe "a canonical team is read-only: refused before parking, parks nothing" do
    let(:team) do
      create(:ai_agent_team, account: account, template_id: SecureRandom.uuid,
                             team_config: { "canonical" => true })
    end

    it "refuses delete_team" do
      result = run(Ai::Tools::TeamManagementTool, action: "delete_team", team_id: team.id)

      expect(result).to include(success: false, canonical: true)
      expect(Ai::DeferredOperation.count).to eq(0)
      expect(Ai::AgentTeam.where(id: team.id)).to exist
    end

    it "refuses remove_team_member" do
      result = run(Ai::Tools::TeamManagementTool, action: "remove_team_member",
                                                   team_id: team.id, agent_id: create(:ai_agent, account: account).id)

      expect(result).to include(success: false, canonical: true)
      expect(Ai::DeferredOperation.count).to eq(0)
    end

    it "refuses again at replay when the team became canonical after it was parked" do
      plain = create(:ai_agent_team, account: account)
      parked = run(Ai::Tools::TeamManagementTool, action: "delete_team", team_id: plain.id)
      expect_parked(parked, "ai.team.delete")
      plain.update!(template_id: SecureRandom.uuid, team_config: { "canonical" => true })

      operation = approve!(parked)

      expect(operation.reload.result.with_indifferent_access).to include(success: false, canonical: true)
      expect(Ai::AgentTeam.where(id: plain.id)).to exist
    end
  end

  describe "approve and replay (delete_ralph_loop, delete_skill)" do
    it "deletes the loop as the original caller once a person approves in their own session" do
      loop_record = create(:ai_ralph_loop, account: account)
      parked = run(Ai::Tools::RalphLoopTool, action: "delete_ralph_loop", loop_id: loop_record.id)
      expect_parked(parked, "ai.ralph_loop.delete")
      expect(Ai::RalphLoop.where(id: loop_record.id)).to exist

      operation = approve!(parked)

      expect(operation.reload.status).to eq("completed")
      expect(operation.result.with_indifferent_access).to include(success: true)
      expect(Ai::RalphLoop.where(id: loop_record.id)).not_to exist
    end

    it "refuses the replay, and keeps the loop, when the caller's grants were all revoked after parking" do
      loop_record = create(:ai_ralph_loop, account: account)
      parked = run(Ai::Tools::RalphLoopTool, action: "delete_ralph_loop", loop_id: loop_record.id)
      expect_parked(parked, "ai.ralph_loop.delete")
      caller_user.roles = []

      operation = approve!(parked)

      expect(Ai::RalphLoop.where(id: loop_record.id)).to exist
      expect(operation.reload.result.with_indifferent_access).to include(success: false, reason: "permission_revoked")
    end

    it "refuses the replay, and keeps the loop, when only the action's own permission was revoked" do
      loop_record = create(:ai_ralph_loop, account: account)
      parked = run(Ai::Tools::RalphLoopTool, action: "delete_ralph_loop", loop_id: loop_record.id)
      expect_parked(parked, "ai.ralph_loop.delete")
      RolePermission.where(role_id: caller_user.roles.select(:id), permission_name: "ai.loops.delete").delete_all

      operation = approve!(parked)

      expect(Ai::RalphLoop.where(id: loop_record.id)).to exist
      expect(operation.reload.result.with_indifferent_access[:error]).to match(/permission denied: ai.loops.delete/)
    end

    it "deletes the skill on approval" do
      skill = create(:ai_skill, account: account)
      parked = run(Ai::Tools::SkillTool, action: "delete_skill", skill_id: skill.id)
      expect_parked(parked, "ai.skill.delete")

      operation = approve!(parked)

      expect(operation.reload.status).to eq("completed")
      expect(Ai::Skill.where(id: skill.id)).not_to exist
    end
  end
end
