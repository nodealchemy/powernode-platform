# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Autonomy::DutyCycleService, type: :service do
  let(:account) { create(:account) }
  let(:provider) { create(:ai_provider, account: account) }
  let(:agent) { create(:ai_agent, account: account, provider: provider) }

  # A duty-cycle action is tagged in execution_context (Option A — no migration).
  def duty_cycle_execution(**attrs)
    create(:ai_agent_execution, account: account, agent: agent,
                                execution_context: { "kind" => "duty_cycle" }, **attrs)
  end

  describe ".duty_cycle_action_count / .daily_limit_exceeded?" do
    # Regression: the daily budget read/wrote a non-existent execution_type column, so it
    # never counted anything. Count today's duty_cycle-tagged executions via execution_context.
    it "counts only today's duty_cycle-tagged executions" do
      duty_cycle_execution
      duty_cycle_execution
      create(:ai_agent_execution, account: account, agent: agent) # untagged -> excluded
      duty_cycle_execution(created_at: 2.days.ago)                 # old -> excluded

      expect(described_class.duty_cycle_action_count(agent)).to eq(2)
    end

    it "daily_limit_exceeded? compares the count against MAX_DAILY_ACTIONS" do
      stub_const("Ai::Autonomy::DutyCycleService::MAX_DAILY_ACTIONS", 2)
      expect(described_class.daily_limit_exceeded?(agent)).to be false

      2.times { duty_cycle_execution }
      expect(described_class.daily_limit_exceeded?(agent)).to be true
    end
  end

  describe "#record_action" do
    let(:ralph_loop) { create(:ai_ralph_loop, account: account) }
    subject(:service) { described_class.new(account: account, agent: agent, ralph_loop: ralph_loop) }
    let(:observation) { double("observation", id: SecureRandom.uuid, title: "High latency on provider") }

    it "persists a duty_cycle-tagged AgentExecution that the budget can count" do
      expect {
        service.send(:record_action, "react_to_alert", observation)
      }.to change(Ai::AgentExecution, :count).by(1)

      exec = Ai::AgentExecution.order(:created_at).last
      expect(exec.execution_context["kind"]).to eq("duty_cycle")
      expect(exec.ai_agent_id).to eq(agent.id)
      expect(described_class.duty_cycle_action_count(agent)).to eq(1)
    end

    # Bug: record_action recorded the agent's RAW ai_provider_id column instead
    # of the RESOLVED provider that actually serves the call
    # (Ai::Agent#resolved_provider). See
    # app/models/concerns/ai/agent/execution.rb for the sibling bug/fix.
    it "records the RESOLVED provider's id, not the raw ai_provider_id column" do
      resolved_provider = create(:ai_provider, account: account, name: "actual-anthropic")
      allow(agent).to receive(:resolved_provider).and_return(resolved_provider)

      service.send(:record_action, "react_to_alert", observation)

      exec = Ai::AgentExecution.order(:created_at).last
      expect(exec.ai_provider_id).to eq(resolved_provider.id)
      expect(exec.ai_provider_id).not_to eq(agent.ai_provider_id)
    end
  end
end
