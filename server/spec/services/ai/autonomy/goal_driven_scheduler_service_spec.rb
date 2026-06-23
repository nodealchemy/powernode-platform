# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Autonomy::GoalDrivenSchedulerService do
  let(:account) { create(:account) }
  let(:agent) { create(:ai_agent, account: account) }
  let(:service) { described_class.new(account: account, agent: agent) }

  describe "kill switch enforcement" do
    # Regression: kill_switch_active? previously queried
    # `Ai::KillSwitchEvent.where(status: "active")`, but that model has NO
    # `status` column (only `event_type` in halt/resume). The canonical halt
    # signal is `account.ai_suspended?` via Ai::Autonomy::KillSwitchService#halted?
    # (set by KillSwitchService#emergency_halt! -> account.suspend_ai!).
    it "reports the kill switch as active when AI is suspended for the account" do
      account.suspend_ai!
      expect(service.send(:kill_switch_active?)).to be true
    end

    it "reports the kill switch as inactive when AI is not suspended" do
      expect(service.send(:kill_switch_active?)).to be false
    end

    it "refuses to execute while the kill switch is engaged" do
      account.suspend_ai!
      expect(service.should_execute_now?).to be false
    end

    it "agrees with KillSwitchService#halted? after an emergency halt" do
      user = create(:user, account: account)
      Ai::Autonomy::KillSwitchService.new(account: account)
                                     .emergency_halt!(reason: "test", triggered_by: user)
      expect(service.send(:kill_switch_active?)).to be true
    end
  end

  describe "duty cycle enforcement" do
    # Regression: duty_cycle_exceeded? called DutyCycleService.new(account:, agent:).exceeded?
    # (wrong ctor args + no such method, swallowed by rescue → always false), and the
    # underlying budget accounting read a non-existent execution_type column. Option A:
    # duty-cycle actions are tagged in execution_context; the gate uses the ralph_loop-free
    # DutyCycleService.daily_limit_exceeded?(agent).
    def duty_cycle_execution
      create(:ai_agent_execution, account: account, agent: agent,
                                  execution_context: { "kind" => "duty_cycle" })
    end

    it "is not exceeded when under the daily budget" do
      stub_const("Ai::Autonomy::DutyCycleService::MAX_DAILY_ACTIONS", 2)
      expect(service.send(:duty_cycle_exceeded?)).to be false
    end

    it "is exceeded once today's duty-cycle budget is reached" do
      stub_const("Ai::Autonomy::DutyCycleService::MAX_DAILY_ACTIONS", 2)
      2.times { duty_cycle_execution }
      expect(service.send(:duty_cycle_exceeded?)).to be true
    end

    it "refuses to schedule an over-budget agent that still has active goals" do
      Ai::AgentGoal.create!(account: account, agent: agent, title: "G", description: "x",
                            goal_type: "creation", status: "active", priority: 3, progress: 0.0)
      stub_const("Ai::Autonomy::DutyCycleService::MAX_DAILY_ACTIONS", 1)
      duty_cycle_execution
      expect(service.should_execute_now?).to be false
    end
  end
end
