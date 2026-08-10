# frozen_string_literal: true

require "rails_helper"

# IMP-e041c835a40d — the scheduled driver that finally CLOSES the core OODA
# loop: RalphLoopClosureService was a complete observe/orient/decide/act/learn
# cycle with zero production call-sites (observations were written every 15
# minutes, rendered once as prompt prose, then deleted).
#
# Activation posture (operator-set constraints):
#   - The cadence flag ai.autonomy.closure_driver_enabled defaults OFF —
#     wiring this driver changes nothing until an operator explicitly enables
#     it (autonomy-cadence activations are never implicit).
#   - The account kill switch (ai_suspended?) refuses the tick.
#   - The control-plane fence is honored via the defined? extension seam:
#     a standby plane never drives cycles.
#   - DutyCycleService's per-agent daily action budget is reused as the
#     cost backstop, plus a hard per-tick agent cap.
RSpec.describe Ai::Autonomy::ClosureDriverService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:provider) { create(:ai_provider, account: account, is_active: true) }
  let(:service) { described_class.new(account: account) }

  def agent_with_active_goal(name)
    agent = create(:ai_agent, account: account, provider: provider, creator: user,
                   status: "active", name: "#{name}-#{SecureRandom.hex(3)}")
    Ai::AgentGoal.create!(account: account, agent: agent, title: "goal for #{name}",
                          goal_type: "maintenance", status: "active", priority: 3)
    agent
  end

  def stub_cycles!
    cycles = []
    allow(Ai::Autonomy::RalphLoopClosureService).to receive(:new) do |account:, agent:|
      cycles << agent.id
      instance_double(Ai::Autonomy::RalphLoopClosureService,
                      execute_cycle: { observe: 0, decide: [], act: [] })
    end
    cycles
  end

  def enable!
    SiteSetting.set(described_class::ENABLED_SETTING, "true")
  end

  it "is disabled by default: no cycles run and the result says so" do
    agent_with_active_goal("idle")
    cycles = stub_cycles!

    result = service.run

    expect(result[:enabled]).to be(false)
    expect(cycles).to be_empty
  end

  it "runs a closure cycle per agent with an active goal when enabled" do
    goal_agent = agent_with_active_goal("driven")
    create(:ai_agent, account: account, provider: provider, creator: user,
           status: "active", name: "goalless-#{SecureRandom.hex(3)}")
    cycles = stub_cycles!
    enable!

    result = service.run

    expect(cycles).to contain_exactly(goal_agent.id)
    expect(result[:cycles_run]).to eq(1)
  end

  it "refuses the tick when the account kill switch is on" do
    agent_with_active_goal("halted")
    cycles = stub_cycles!
    enable!
    allow_any_instance_of(Account).to receive(:ai_suspended?).and_return(true)

    result = service.run

    expect(result[:halted]).to be(true)
    expect(cycles).to be_empty
  end

  it "never drives cycles from a standby control plane (extension fence seam)" do
    agent_with_active_goal("fenced")
    cycles = stub_cycles!
    enable!
    skip "system extension not loaded" unless defined?(::System::Autonomy::ControlPlaneRole)
    allow(::System::Autonomy::ControlPlaneRole).to receive(:active?).and_return(false)

    result = service.run

    expect(result[:standby]).to be(true)
    expect(cycles).to be_empty
  end

  it "skips agents over the DutyCycleService daily budget (cost backstop)" do
    over_budget = agent_with_active_goal("spender")
    frugal = agent_with_active_goal("frugal")
    cycles = stub_cycles!
    enable!
    allow(Ai::Autonomy::DutyCycleService).to receive(:daily_limit_exceeded?) do |agent|
      agent.id == over_budget.id
    end

    result = service.run

    expect(cycles).to contain_exactly(frugal.id)
    expect(result[:skipped_over_budget]).to eq(1)
  end

  it "caps the number of agents driven per tick" do
    (described_class::AGENTS_PER_TICK + 2).times { |i| agent_with_active_goal("many#{i}") }
    cycles = stub_cycles!
    enable!

    service.run

    expect(cycles.size).to eq(described_class::AGENTS_PER_TICK)
  end

  it "isolates a failing agent's cycle (others still run)" do
    boom = agent_with_active_goal("boom")
    fine = agent_with_active_goal("fine")
    enable!
    allow(Ai::Autonomy::RalphLoopClosureService).to receive(:new) do |account:, agent:|
      double_cycle = instance_double(Ai::Autonomy::RalphLoopClosureService)
      if agent.id == boom.id
        allow(double_cycle).to receive(:execute_cycle).and_raise(StandardError, "cycle exploded")
      else
        allow(double_cycle).to receive(:execute_cycle).and_return({ observe: 0 })
      end
      double_cycle
    end

    result = service.run

    expect(result[:cycles_run]).to eq(1)
    expect(result[:cycles_failed]).to eq(1)
  end
end
