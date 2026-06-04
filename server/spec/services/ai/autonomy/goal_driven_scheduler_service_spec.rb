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
end
