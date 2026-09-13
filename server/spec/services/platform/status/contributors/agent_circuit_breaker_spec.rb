# frozen_string_literal: true

require "rails_helper"

# Component status plane, increment A3 — the `agent_circuit_breaker` core
# contributor over Ai::CircuitBreaker (kill-switch layer 5).
RSpec.describe Platform::Status::Contributors::AgentCircuitBreaker do
  subject(:contributor) { described_class.new }

  let(:account) { create(:account) }
  let(:agent) { create(:ai_agent, account: account) }
  let(:unknown_reason) { Platform::Status::Contributors::EnumConditions::UNKNOWN_REASON }

  def only_condition(breaker) = contributor.conditions_for(breaker).first

  def enumerate(for_account)
    [].tap { |acc| contributor.each_component(for_account) { |record| acc << record } }
  end

  describe "the contract" do
    it "answers the registry key and is account scoped" do
      expect(described_class::KIND).to eq("agent_circuit_breaker")
      expect(contributor.kind).to eq("agent_circuit_breaker")
      expect(contributor.account_scoped?).to be(true)
    end

    it "presents a string icon name, a label and a group order" do
      expect(contributor.presentation).to eq(
        "icon" => "CircuitBoard", "label" => "Agent Circuit Breaker", "group_order" => 40
      )
    end

    it "names the breaker by its agent and action type, and links to the agent" do
      breaker = create(:ai_circuit_breaker, account: account, agent: agent, action_type: "execute_tool")

      expect(contributor.display_name_for(breaker)).to eq("#{agent.name} · execute_tool")
      expect(contributor.links_for(breaker))
        .to eq([ { "label" => "Agent", "path" => "/app/ai/agents/#{agent.id}" } ])
    end

    it "declares no dependencies and no A3 actions" do
      breaker = create(:ai_circuit_breaker, account: account, agent: agent)

      expect(contributor.dependencies_for(breaker)).to eq([])
      expect(contributor.actions_for(breaker)).to eq([])
    end
  end

  describe "state coverage" do
    it "maps every value of Ai::CircuitBreaker::STATES" do
      expect(contributor.mapped_values(described_class::STATE_CONDITIONS))
        .to eq(::Ai::CircuitBreaker::STATES.sort)
    end

    it "gives every state a reason that is not UnknownStatus" do
      breaker = build(:ai_circuit_breaker, account: account, agent: agent)

      ::Ai::CircuitBreaker::STATES.each do |state|
        breaker.state = state
        condition = only_condition(breaker)

        expect(condition).not_to be_nil, "no condition for #{state}"
        expect(condition["reason"]).not_to eq(unknown_reason), "#{state} fell through to UnknownStatus"
      end
    end

    it "reports an out-of-band state as unknown/UnknownStatus, never ok" do
      breaker = build(:ai_circuit_breaker, account: account, agent: agent)
      breaker.state = "welded_shut"

      condition = only_condition(breaker)

      expect(condition["status"]).to eq(Platform::Status::Condition::UNKNOWN)
      expect(condition["reason"]).to eq(unknown_reason)
      expect(condition["evidence"]["unmapped_value"]).to eq("welded_shut")
    end

    it "calls an open breaker degraded and a half-open one progressing" do
      breaker = build(:ai_circuit_breaker, account: account, agent: agent)

      {
        "closed" => Platform::ComponentStatus::OK,
        "open" => Platform::ComponentStatus::DEGRADED,
        "half_open" => Platform::ComponentStatus::PROGRESSING
      }.each do |state, verdict|
        breaker.state = state

        expect(Platform::Status::Condition.verdict_for_set(contributor.conditions_for(breaker)))
          .to eq(verdict), "state=#{state}"
      end
    end

    # This is what tells an operator that a trip came from the kill switch
    # rather than from real upstream failures.
    it "carries the reason the breaker last moved as evidence" do
      breaker = create(:ai_circuit_breaker, account: account, agent: agent)
      breaker.trip!(reason: "kill_switch_activated")

      evidence = only_condition(breaker)["evidence"]

      expect(evidence["state"]).to eq("open")
      expect(evidence["last_transition_reason"]).to eq("kill_switch_activated")
      expect(evidence).to include("failure_threshold" => breaker.failure_threshold)
    end

    it "omits the transition reason when the breaker has never moved" do
      breaker = create(:ai_circuit_breaker, account: account, agent: agent, history: [])

      expect(only_condition(breaker)["evidence"]).not_to have_key("last_transition_reason")
    end
  end

  describe "#each_component" do
    it "yields only this account's breakers" do
      mine = create(:ai_circuit_breaker, account: account, agent: agent)
      other_account = create(:account)
      theirs = create(:ai_circuit_breaker, account: other_account,
                                           agent: create(:ai_agent, account: other_account))

      ids = enumerate(account).map(&:id)

      expect(ids).to eq([ mine.id ])
      expect(ids).not_to include(theirs.id)
    end

    # F2. The scope is the AGENT's account, matching kill-switch layer 5, so
    # the kind shows exactly the breakers a halt reaches.
    #
    # A GLOBAL agent's breaker is stamped with the calling service's account
    # (`Ai::Autonomy::CircuitBreakerService#find_or_create` sets
    # `cb.account = account`), so this row carries X while its agent carries
    # NULL. Layer 5 (`where(ai_agents: {account_id: X})`) never opens it, so
    # showing it in X's plane would be a green row claiming a halt reached a
    # breaker it never touched.
    #
    # The underlying defect — `find_or_create_by!(agent_id:, action_type:)`
    # carries no account and the unique index is on that pair, so a global
    # agent has one breaker platform-wide — is filed as its own offer and is
    # not fixed here.
    it "does not enumerate a global agent's breaker, because a halt never reaches it" do
      global_agent = create(:ai_agent, :global)
      stamped_with_our_account = create(:ai_circuit_breaker, account: account, agent: global_agent)

      expect(enumerate(account).map(&:id)).not_to include(stamped_with_our_account.id)
    end

    it "does enumerate a breaker whose AGENT is ours even when the breaker row is not" do
      # The other arm: the agent's account is what decides, both ways.
      elsewhere = create(:account)
      ours_by_agent = create(:ai_circuit_breaker, account: elsewhere, agent: agent,
                                                  action_type: "spawn_task")

      expect(enumerate(account).map(&:id)).to include(ours_by_agent.id)
    end

    it "excludes breakers belonging to an archived agent and keeps merely inactive ones" do
      archived_agent = create(:ai_agent, account: account, status: "archived")
      inactive_agent = create(:ai_agent, account: account, status: "inactive")
      archived = create(:ai_circuit_breaker, account: account, agent: archived_agent)
      inactive = create(:ai_circuit_breaker, account: account, agent: inactive_agent)

      ids = enumerate(account).map(&:id)

      expect(ids).to include(inactive.id)
      expect(ids).not_to include(archived.id)
    end

    it "yields nothing without an account" do
      create(:ai_circuit_breaker, account: account, agent: agent)

      expect(enumerate(nil)).to eq([])
    end
  end
end
