# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::TeamAuthorityService, type: :service do
  let(:account) { create(:account) }
  let(:team) { create(:ai_agent_team, account: account, team_config: team_config) }
  let(:team_config) { {} }

  subject(:service) { described_class.new(team: team) }

  # Shared actor helpers
  let(:manager_role) { create(:ai_team_role, :manager, agent_team: team, account: account) }
  let(:worker_role) { create(:ai_team_role, agent_team: team, account: account, role_type: "worker") }
  let(:specialist_role) { create(:ai_team_role, :specialist, agent_team: team, account: account) }
  let(:reviewer_role) { create(:ai_team_role, :reviewer, agent_team: team, account: account) }

  let(:lead_member) { create(:ai_agent_team_member, :lead, team: team) }
  let(:coordinator_member) { create(:ai_agent_team_member, :coordinator, team: team) }
  let(:executor_member) { create(:ai_agent_team_member, team: team, role: "executor") }
  let(:reviewer_member) { create(:ai_agent_team_member, :reviewer, team: team) }

  # ===========================================================================
  # #authority_level
  # ===========================================================================

  describe "#authority_level" do
    it "returns 0 for nil (human)" do
      expect(service.authority_level(nil)).to eq(0)
    end

    it "returns 1 for manager TeamRole" do
      expect(service.authority_level(manager_role)).to eq(1)
    end

    it "returns 2 for specialist TeamRole" do
      expect(service.authority_level(specialist_role)).to eq(2)
    end

    it "returns 3 for worker TeamRole" do
      expect(service.authority_level(worker_role)).to eq(3)
    end

    it "returns 4 for reviewer TeamRole" do
      expect(service.authority_level(reviewer_role)).to eq(4)
    end

    it "returns 1 for lead AgentTeamMember" do
      expect(service.authority_level(lead_member)).to eq(1)
    end

    it "returns 2 for coordinator AgentTeamMember" do
      expect(service.authority_level(coordinator_member)).to eq(2)
    end

    it "returns 3 for executor AgentTeamMember" do
      expect(service.authority_level(executor_member)).to eq(3)
    end

    it "returns 4 for reviewer AgentTeamMember" do
      expect(service.authority_level(reviewer_member)).to eq(4)
    end
  end

  # ===========================================================================
  # #authorize_delegation!
  # ===========================================================================

  describe "#authorize_delegation!" do
    it "allows human (nil) to delegate to anyone" do
      expect { service.authorize_delegation!(nil, worker_role) }.not_to raise_error
    end

    it "allows manager with can_delegate to delegate to worker" do
      expect { service.authorize_delegation!(manager_role, worker_role) }.not_to raise_error
    end

    it "raises when actor lacks delegation authority" do
      non_delegating_role = create(:ai_team_role, agent_team: team, account: account,
                                    role_type: "worker", can_delegate: false)

      expect {
        service.authorize_delegation!(non_delegating_role, reviewer_role)
      }.to raise_error(Ai::TeamAuthorityService::AuthorityViolation, /delegation authority/)
    end

    it "raises when actor tries to delegate upward" do
      delegating_worker = create(:ai_team_role, agent_team: team, account: account,
                                  role_type: "worker", can_delegate: true)

      expect {
        service.authorize_delegation!(delegating_worker, manager_role)
      }.to raise_error(Ai::TeamAuthorityService::AuthorityViolation, /cannot delegate/)
    end

    context "with lateral_delegation_allowed override" do
      let(:team_config) { { "authority_overrides" => { "lateral_delegation_allowed" => true } } }

      it "allows same-level delegation" do
        another_worker = create(:ai_team_role, agent_team: team, account: account,
                                 role_type: "worker", can_delegate: true)

        expect { service.authorize_delegation!(another_worker, worker_role) }.not_to raise_error
      end
    end

    context "with specialists_can_delegate override" do
      let(:team_config) { { "authority_overrides" => { "specialists_can_delegate" => true } } }

      it "allows specialist AgentTeamMember to delegate" do
        # specialists_can_delegate override applies to AgentTeamMember (checked via authority_level)
        specialist_member = create(:ai_agent_team_member, :coordinator, team: team)

        expect { service.authorize_delegation!(specialist_member, executor_member) }.not_to raise_error
      end
    end
  end

  # ===========================================================================
  # #authorize_escalation!
  # ===========================================================================

  describe "#authorize_escalation!" do
    it "allows human (nil) to skip authorization" do
      expect { service.authorize_escalation!(nil, manager_role) }.not_to raise_error
    end

    it "allows worker to escalate to specialist (one level up)" do
      expect { service.authorize_escalation!(worker_role, specialist_role) }.not_to raise_error
    end

    it "raises when actor lacks escalation authority" do
      non_escalating = create(:ai_team_role, agent_team: team, account: account,
                               role_type: "worker", can_escalate: false)

      expect {
        service.authorize_escalation!(non_escalating, manager_role)
      }.to raise_error(Ai::TeamAuthorityService::AuthorityViolation, /escalation authority/)
    end

    it "raises when target is lower authority than actor" do
      expect {
        service.authorize_escalation!(manager_role, worker_role)
      }.to raise_error(Ai::TeamAuthorityService::AuthorityViolation, /cannot escalate/)
    end

    it "raises for skip-level escalation without override" do
      expect {
        service.authorize_escalation!(worker_role, manager_role)
      }.to raise_error(Ai::TeamAuthorityService::AuthorityViolation, /skip-level/)
    end

    context "with workers_can_escalate_directly override" do
      let(:team_config) { { "authority_overrides" => { "workers_can_escalate_directly" => true } } }

      it "allows skip-level escalation" do
        expect { service.authorize_escalation!(worker_role, manager_role) }.not_to raise_error
      end
    end
  end

  # ===========================================================================
  # #authorize_message!
  # ===========================================================================

  describe "#authorize_message!" do
    it "allows human (nil) to send any message type" do
      expect { service.authorize_message!(nil, worker_role, "task_assignment") }.not_to raise_error
    end

    it "allows downward-only messages from higher to lower authority" do
      expect { service.authorize_message!(manager_role, worker_role, "task_assignment") }.not_to raise_error
    end

    it "raises for downward-only messages sent upward" do
      expect {
        service.authorize_message!(worker_role, manager_role, "task_assignment")
      }.to raise_error(Ai::TeamAuthorityService::AuthorityViolation, /only be sent downward/)
    end

    it "allows upward-only messages from lower to higher authority" do
      expect { service.authorize_message!(worker_role, manager_role, "escalation") }.not_to raise_error
    end

    it "raises for upward-only messages sent downward" do
      expect {
        service.authorize_message!(manager_role, worker_role, "escalation")
      }.to raise_error(Ai::TeamAuthorityService::AuthorityViolation, /only be sent upward/)
    end

    it "allows broadcast from level 2 or higher" do
      expect { service.authorize_message!(specialist_role, worker_role, "broadcast") }.not_to raise_error
    end

    it "raises for broadcast from level 3 (worker)" do
      expect {
        service.authorize_message!(worker_role, manager_role, "broadcast")
      }.to raise_error(Ai::TeamAuthorityService::AuthorityViolation, /broadcast authority/)
    end
  end

  # ===========================================================================
  # #authorize_task_modification!
  # ===========================================================================

  describe "#authorize_task_modification!" do
    let(:task_double) { double("Task", assigned_role: worker_role, assigned_agent_id: nil) }

    it "allows human (nil) to modify any task" do
      expect { service.authorize_task_modification!(nil, task_double, :cancel) }.not_to raise_error
    end

    it "allows manager to cancel a worker's task" do
      expect { service.authorize_task_modification!(manager_role, task_double, :cancel) }.not_to raise_error
    end

    it "raises when worker tries to cancel a peer's task" do
      expect {
        service.authorize_task_modification!(worker_role, task_double, :cancel)
      }.to raise_error(Ai::TeamAuthorityService::AuthorityViolation)
    end

    it "allows specialist to modify_priority" do
      expect { service.authorize_task_modification!(specialist_role, task_double, :modify_priority) }.not_to raise_error
    end

    it "raises when worker tries to modify_priority" do
      expect {
        service.authorize_task_modification!(worker_role, task_double, :modify_priority)
      }.to raise_error(Ai::TeamAuthorityService::AuthorityViolation, /modify task priority/)
    end
  end

  # ===========================================================================
  # #authorize_memory_control!
  # ===========================================================================

  describe "#authorize_memory_control!" do
    let(:pool_double) { double("MemoryPool") }

    it "allows human (nil)" do
      expect { service.authorize_memory_control!(nil, pool_double) }.not_to raise_error
    end

    it "allows manager (level 1)" do
      expect { service.authorize_memory_control!(manager_role, pool_double) }.not_to raise_error
    end

    it "allows specialist (level 2)" do
      expect { service.authorize_memory_control!(specialist_role, pool_double) }.not_to raise_error
    end

    it "raises for worker (level 3)" do
      expect {
        service.authorize_memory_control!(worker_role, pool_double)
      }.to raise_error(Ai::TeamAuthorityService::AuthorityViolation, /memory access/)
    end
  end

  # ===========================================================================
  # #authorize_review!
  # ===========================================================================

  describe "#authorize_review!" do
    it "allows when reviewer is different from task assignee" do
      task_double = double("Task", assigned_agent_id: SecureRandom.uuid)

      expect { service.authorize_review!(reviewer_role, task_double) }.not_to raise_error
    end

    it "raises for self-review" do
      shared_agent = create(:ai_agent, account: account)
      role_with_agent = create(:ai_team_role, :reviewer, agent_team: team, account: account, ai_agent: shared_agent)
      task_double = double("Task", assigned_agent_id: shared_agent.id)

      expect {
        service.authorize_review!(role_with_agent, task_double)
      }.to raise_error(Ai::TeamAuthorityService::AuthorityViolation, /own task/)
    end
  end

  # ===========================================================================
  # #authorize_authority_change!
  # ===========================================================================

  describe "#authorize_authority_change!" do
    it "allows human (nil) to change authority" do
      expect { service.authorize_authority_change!(nil, worker_role, { role: "specialist" }) }.not_to raise_error
    end

    it "allows manager to change worker role" do
      expect { service.authorize_authority_change!(manager_role, worker_role, { role: "specialist" }) }.not_to raise_error
    end

    it "raises when specialist tries to change authority" do
      expect {
        service.authorize_authority_change!(specialist_role, worker_role, { role: "reviewer" })
      }.to raise_error(Ai::TeamAuthorityService::AuthorityViolation, /change member authority/)
    end

    it "allows manager to promote worker to same level (manager)" do
      # Manager (level 1) promoting to manager (level 1): new_level == actor_level, so allowed
      expect { service.authorize_authority_change!(manager_role, worker_role, { role: "manager" }) }.not_to raise_error
    end

    it "raises when non-human tries to grant lead status" do
      expect {
        service.authorize_authority_change!(manager_role, worker_role, { is_lead: true })
      }.to raise_error(Ai::TeamAuthorityService::AuthorityViolation, /Only human users/)
    end

    it "allows human to grant lead status" do
      expect { service.authorize_authority_change!(nil, worker_role, { is_lead: true }) }.not_to raise_error
    end
  end

  # ===========================================================================
  # #authorize_member_management!
  # ===========================================================================

  describe "#authorize_member_management!" do
    it "allows human (nil) for all actions" do
      %i[add_member remove_member set_role].each do |action|
        expect { service.authorize_member_management!(nil, action) }.not_to raise_error
      end
    end

    it "allows specialist to add members" do
      expect { service.authorize_member_management!(specialist_role, :add_member) }.not_to raise_error
    end

    it "raises when worker tries to add members" do
      expect {
        service.authorize_member_management!(worker_role, :add_member)
      }.to raise_error(Ai::TeamAuthorityService::AuthorityViolation, /add members/)
    end

    it "allows manager to remove members" do
      expect { service.authorize_member_management!(manager_role, :remove_member) }.not_to raise_error
    end

    it "raises when specialist tries to remove members" do
      expect {
        service.authorize_member_management!(specialist_role, :remove_member)
      }.to raise_error(Ai::TeamAuthorityService::AuthorityViolation, /remove members/)
    end

    it "allows manager to set roles" do
      expect { service.authorize_member_management!(manager_role, :set_role) }.not_to raise_error
    end

    it "raises when specialist tries to set roles" do
      expect {
        service.authorize_member_management!(specialist_role, :set_role)
      }.to raise_error(Ai::TeamAuthorityService::AuthorityViolation, /set member roles/)
    end
  end
end
