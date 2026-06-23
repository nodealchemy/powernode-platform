# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Autonomy::RalphLoopClosureService, type: :service do
  let(:account) { create(:account) }
  let(:agent) { create(:ai_agent, account: account) }

  subject(:service) { described_class.new(account: account, agent: agent) }

  before do
    # Observe/orient: no observations so the cycle reaches the decide/act loop cleanly.
    pipeline = instance_double(Ai::Autonomy::ObservationPipelineService, run: [])
    allow(Ai::Autonomy::ObservationPipelineService).to receive(:new).and_return(pipeline)
  end

  describe "#execute_cycle decide/act loop" do
    # Regression: the per-cycle loop pushed to results[:decide] then `break if size >= 5`
    # BEFORE the case dispatch and `results[:act] << action`, so the 5th decided action
    # was recorded but never dispatched/acted (decide.size 5, act.size 4) — one actionable
    # item silently dropped every cycle.
    it "acts on every decided action up to the per-cycle cap of 5" do
      # 6 no-op actions (nil ids hit the `if found` guards, so no heavy work runs);
      # the cap should stop at 5, and all 5 decided must also be acted.
      actions = Array.new(6) { |i| { type: :evaluate_plan, plan_id: nil, seq: i } }
      scheduler = instance_double(Ai::Autonomy::GoalDrivenSchedulerService)
      allow(scheduler).to receive(:next_action).and_return(*actions, nil)
      allow(Ai::Autonomy::GoalDrivenSchedulerService).to receive(:new).and_return(scheduler)

      results = service.execute_cycle

      expect(results[:decide].size).to eq(5)
      expect(results[:act].size).to eq(5)
      expect(results[:act].size).to eq(results[:decide].size)
    end

    it "acts on all actions when fewer than the cap are available" do
      actions = Array.new(3) { |i| { type: :evaluate_plan, plan_id: nil, seq: i } }
      scheduler = instance_double(Ai::Autonomy::GoalDrivenSchedulerService)
      allow(scheduler).to receive(:next_action).and_return(*actions, nil)
      allow(Ai::Autonomy::GoalDrivenSchedulerService).to receive(:new).and_return(scheduler)

      results = service.execute_cycle

      expect(results[:decide].size).to eq(3)
      expect(results[:act].size).to eq(3)
    end
  end
end
