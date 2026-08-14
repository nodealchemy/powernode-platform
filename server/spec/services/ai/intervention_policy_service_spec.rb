# frozen_string_literal: true

require "rails_helper"

# IMP-bfbf8052e179 — audience separation in policy RESOLUTION.
#
# Ai::InterventionPolicy#agent_matches? admits a nil-agent row for ANY caller,
# and #resolve used to prefer agent-scoped rows only when the calling agent HAD
# matching ones. An agent with no scoped row for a category therefore caught
# rows seeded for the OPERATOR (agent-less) audience and inherited their
# (usually laxer) verb instead of the require_approval default — a human-intent
# row silently widening agent autonomy.
#
# The contract now: when an agent is present, resolve considers ONLY rows
# scoped to that agent; nil-agent rows bind exclusively on the agent-less
# (operator) path, and an agent unmatched by any scoped row falls to the
# require_approval default.
RSpec.describe Ai::InterventionPolicyService do
  let(:account) { create(:account) }
  let(:service) { described_class.new(account: account) }
  let(:agent)   { create(:ai_agent, account: account) }

  before { Ai::InterventionPolicy.register_category!("widget.create") }

  def create_policy!(policy:, ai_agent_id: nil, scope: "action_type",
                     priority: 5, conditions: {}, user_id: nil)
    Ai::InterventionPolicy.create!(
      account: account,
      scope: scope,
      action_category: "widget.create",
      policy: policy,
      priority: priority,
      is_active: true,
      ai_agent_id: ai_agent_id,
      user_id: user_id,
      conditions: conditions
    )
  end

  describe "#resolve audience separation (IMP-bfbf8052e179)" do
    context "with an operator-audience (nil-agent) notify_and_proceed row" do
      let!(:operator_row) do
        create_policy!(policy: "notify_and_proceed",
                       conditions: { "trust_tier_minimum" => "monitored" })
      end

      it "applies the row for an agent-less operator caller" do
        result = service.resolve(action_category: "widget.create", agent: nil)

        expect(result[:policy]).to eq("notify_and_proceed")
        expect(result[:record]).to eq(operator_row)
      end

      # The finding's exact shape: a normal-tier agent with NO scoped row for
      # the category satisfied the row's trust_tier_minimum and inherited
      # notify_and_proceed instead of the human-gate default.
      it "keeps an agent with no scoped row on the require_approval default" do
        create(:ai_agent_trust_score, :monitored, account: account, agent: agent)

        result = service.resolve(action_category: "widget.create", agent: agent)

        expect(result[:policy]).to eq("require_approval")
        expect(result[:record]).to be_nil,
                                   "an operator-audience row bound an agent dispatch"
      end

      # Positive twin: the agent-scoped preference is unchanged when scoped
      # rows exist.
      it "still resolves an agent with a scoped row against its own row" do
        agent_row = create_policy!(policy: "require_approval", scope: "agent",
                                   ai_agent_id: agent.id, priority: 10,
                                   conditions: { "trust_tier_minimum" => "monitored" })
        create(:ai_agent_trust_score, :monitored, account: account, agent: agent)

        result = service.resolve(action_category: "widget.create", agent: agent)

        expect(result[:record]).to eq(agent_row)
        expect(result[:policy]).to eq("require_approval")
      end
    end

    # An emergency demotion is designed to knock the agent's own row out via
    # its trust_tier_minimum condition so resolution escalates to the default.
    # Before the contract change, an UNCONDITIONED nil-agent row caught that
    # fall and quietly kept the demoted agent on notify_and_proceed. Now the
    # escalation holds regardless of the operator row's conditions.
    it "escalates a demoted agent to the default instead of an unconditioned nil-agent fallback" do
      create_policy!(policy: "notify_and_proceed", scope: "agent",
                     ai_agent_id: agent.id, priority: 10,
                     conditions: { "trust_tier_minimum" => "monitored" })
      create_policy!(policy: "notify_and_proceed") # no conditions
      create(:ai_agent_trust_score, account: account, agent: agent) # tier "supervised"

      result = service.resolve(action_category: "widget.create", agent: agent)

      expect(result[:policy]).to eq("require_approval")
      expect(result[:record]).to be_nil,
                                 "a nil-agent row became a fallback for a demoted agent"
    end

    # A user-scoped row with no agent scope is still an agent-less-audience
    # row: it binds the human's own requests, not an agent acting in that
    # user's context.
    it "does not bind a user-scoped nil-agent row to an agent acting for that user" do
      user = create(:user, account: account)
      user_row = create_policy!(policy: "auto_approve", user_id: user.id)
      create(:ai_agent_trust_score, :monitored, account: account, agent: agent)

      expect(service.resolve(action_category: "widget.create", agent: nil, user: user)[:record])
        .to eq(user_row)
      expect(service.resolve(action_category: "widget.create", agent: agent, user: user)[:policy])
        .to eq("require_approval")
    end
  end
end
