# frozen_string_literal: true

require "rails_helper"

# IMP-cb36021d4094 (superseding IMP-bfbf8052e179) — audience separation in
# policy RESOLUTION, keyed on `scope`.
#
# Ai::InterventionPolicy#agent_matches? admits a nil-agent row for ANY caller,
# and #resolve originally preferred agent-scoped rows only when the calling
# agent HAD matching ones. An agent with no scoped row therefore caught rows
# seeded for the OPERATOR audience and inherited their laxer verb —
# IMP-bfbf8052e179, correctly fixed.
#
# That fix cut on `ai_agent_id` nil-ness, which collapses THREE audiences into
# two. Ai::InterventionPolicy::SCOPES names all three, and the cut has to
# honour all three:
#
#   scope "agent"       — binds only the agent it names.
#   scope "action_type" — the operator path (AgentSetupHelpers
#                         .upsert_operator_policies!). Agent-less callers only.
#   scope "global"      — the account-wide floor, agent-BINDING by design.
#
# Keying on ai_agent_id discarded the global audience along with the operator
# one: an operator's account-wide `block` stopped binding agents entirely
# (fail-OPEN — it degraded to require_approval, which any approver may then
# authorise), and a global `auto_approve` degraded to require_approval.
# server/db/seeds/autonomy_data_seed.rb seeds status_update/proposal/escalation
# at scope "global", and Ai::AgentOutreachService resolves them with an agent
# ALWAYS set, so the regression reached core's own outreach path.
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

  # The five-assertion oracle for IMP-cb36021d4094. All five must hold in the
  # same run: satisfying only the first is exactly what a wholesale revert of
  # IMP-bfbf8052e179 does, and it re-breaks the operator path (#3) invisibly.
  describe "#resolve three-audience separation (IMP-cb36021d4094)" do
    let(:user) { create(:user, account: account) }

    # 1. THE FIX. An operator's account-wide block must bind an agent. On the
    #    ai_agent_id cut this returned require_approval — and require_approval
    #    is not a denial: Ai::AutonomyGate parks it as an ApprovalRequest whose
    #    default chain resolves to every active user, so a row meaning "never"
    #    became "any user may authorise this".
    it "binds a scope-global block to an agent caller" do
      row = create_policy!(policy: "block", scope: "global")

      result = service.resolve(action_category: "widget.create", agent: agent)

      expect(result[:policy]).to eq("block")
      expect(result[:record]).to eq(row),
                                 "an account-wide block did not bind an agent — fail-OPEN"
    end

    # 2. CONTROL — passes on HEAD by construction, and must keep passing. This
    #    is the audience IMP-bfbf8052e179 set out to separate.
    it "still skips a scope-action_type row for an agent caller" do
      create_policy!(policy: "block", scope: "action_type")

      result = service.resolve(action_category: "widget.create", agent: agent)

      expect(result[:policy]).to eq("require_approval")
      expect(result[:record]).to be_nil,
                                 "an operator-path row bound an agent dispatch (IMP-bfbf8052e179 regressed)"
    end

    # 3. CONTROL — the half a naive revert silently destroys. The operator path
    #    must keep reading its own rows.
    it "still binds a scope-action_type row for an operator caller" do
      row = create_policy!(policy: "block", scope: "action_type")

      result = service.resolve(action_category: "widget.create", agent: nil, user: user)

      expect(result[:policy]).to eq("block")
      expect(result[:record]).to eq(row),
                                 "the operator path lost its own row — IMP-bfbf8052e179's fix was reverted"
    end

    # 4. The documented precedence at the top of #resolve — user+agent > user >
    #    agent > global — is false for agent callers unless a user-scoped row in
    #    an agent-binding audience reaches them. `user_id` narrows WITHIN an
    #    audience; it is not an audience of its own.
    it "binds a user-scoped row in the global audience to an agent acting for that user" do
      row = create_policy!(policy: "block", scope: "global", user_id: user.id)

      result = service.resolve(action_category: "widget.create", agent: agent, user: user)

      expect(result[:record]).to eq(row),
                                 "a user-scoped global row did not reach an agent acting for that user"
      expect(result[:policy]).to eq("block")
    end

    # 5. The fail-SAFE half of the same defect. Restoring only the restrictive
    #    direction would leave the global audience half-bound, and half-bound is
    #    indistinguishable from working right up until an operator relaxes a
    #    category and nothing changes.
    it "binds a scope-global auto_approve to an agent caller" do
      row = create_policy!(policy: "auto_approve", scope: "global")

      result = service.resolve(action_category: "widget.create", agent: agent)

      expect(result[:policy]).to eq("auto_approve")
      expect(result[:record]).to eq(row)
    end

    # An agent's OWN row still out-ranks the global floor — the cut widens the
    # admitted set, it must not reorder what wins inside it.
    it "prefers the agent's own row over a global row" do
      create_policy!(policy: "auto_approve", scope: "global")
      own = create_policy!(policy: "block", scope: "agent",
                           ai_agent_id: agent.id, priority: 10)

      result = service.resolve(action_category: "widget.create", agent: agent)

      expect(result[:record]).to eq(own)
      expect(result[:policy]).to eq("block")
    end

    # A row whose scope says "agent" but names no agent is malformed. The cut is
    # an allowlist on scope "global" rather than a denylist on "action_type"
    # precisely so such a row cannot bind every agent in the account, and so a
    # scope added to SCOPES later is non-binding until someone decides it.
    it "does not let a scope-agent row with a nil ai_agent_id bind an agent" do
      create_policy!(policy: "auto_approve", scope: "agent", ai_agent_id: nil)

      result = service.resolve(action_category: "widget.create", agent: agent)

      expect(result[:policy]).to eq("require_approval")
      expect(result[:record]).to be_nil
    end
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

    # A user-scoped row in the OPERATOR audience (scope "action_type") binds the
    # human's own requests, not an agent acting in that user's context — the
    # `user_id` narrows the audience its `scope` names, it does not change it.
    # The scope-"global" twin of this example is assertion 4 above, where the
    # same user row DOES reach the agent (IMP-cb36021d4094).
    it "does not bind a user-scoped action_type row to an agent acting for that user" do
      user = create(:user, account: account)
      user_row = create_policy!(policy: "auto_approve", scope: "action_type", user_id: user.id)
      create(:ai_agent_trust_score, :monitored, account: account, agent: agent)

      expect(service.resolve(action_category: "widget.create", agent: nil, user: user)[:record])
        .to eq(user_row)
      expect(service.resolve(action_category: "widget.create", agent: agent, user: user)[:policy])
        .to eq("require_approval")
    end
  end

  # IMP-73dff8186c1e — a notification-VOLUME condition must never act as a
  # denial switch. Exhausting "max_daily_notifications" used to rewrite the
  # verb to "silent", and every autonomy consumer (Ai::AutonomyGate,
  # System::Fleet::FleetAutonomyService, System::CveOps::CveResponderService)
  # folds "silent" into its "block" branch — so the categories an operator had
  # deliberately relaxed to notify_and_proceed were exactly the ones that
  # hard-refused (422) every gated write for the rest of the day.
  #
  # The contract now: the cap degrades AUTHORISATION only as far as
  # require_approval (parked, not refused) and reports the DELIVERY half
  # out-of-band, so a notification budget can never deny an action.
  describe "#resolve under an exhausted max_daily_notifications (IMP-73dff8186c1e)" do
    let(:user) { create(:user, account: account) }

    let!(:relaxed_row) do
      create_policy!(policy: "notify_and_proceed",
                     conditions: { "max_daily_notifications" => 2 })
    end

    def send_ai_notifications!(count)
      count.times do
        create(:notification, account: account, user: user,
                              notification_type: "agent_status_update", category: "ai")
      end
    end

    # Positive control for the whole block: with headroom the row's own verb
    # survives untouched, so every assertion below is about the cap and not
    # about resolution generally.
    it "leaves the row's verb and channels intact while the cap has headroom" do
      send_ai_notifications!(1)

      result = service.resolve(action_category: "widget.create", user: user)

      expect(result[:policy]).to eq("notify_and_proceed")
      expect(result[:channels]).to eq(%w[notification])
      expect(result[:notifications_suppressed]).to be_falsey
    end

    it "degrades to require_approval once the cap is reached" do
      send_ai_notifications!(2)

      expect(service.resolve(action_category: "widget.create", user: user)[:policy])
        .to eq("require_approval")
    end

    # The load-bearing negation, stated against the consumers rather than the
    # replacement verb: whatever this branch returns, it must not be a verb any
    # gate reads as a denial. Ai::AutonomyGate's rejecting branch is
    # `when "block", "silent"`.
    it "never returns a verb the autonomy gates treat as a denial" do
      send_ai_notifications!(5)

      expect(service.resolve(action_category: "widget.create", user: user)[:policy])
        .not_to be_in(%w[silent block])
    end

    # The delivery half still has to travel, or the fix would trade a false
    # denial for a cap that no longer suppresses anything.
    it "reports the suppressed delivery out-of-band, with the reason and the row" do
      send_ai_notifications!(2)

      result = service.resolve(action_category: "widget.create", user: user)

      expect(result[:notifications_suppressed]).to be(true)
      expect(result[:channels]).to eq([])
      expect(result[:reason]).to eq("Daily notification limit reached")
      expect(result[:record]).to eq(relaxed_row)
    end

    # Asymmetric reachability, pinned so a future guard change is visible: the
    # cap is guarded on `user`, so an agent-less-user dispatch never trips it.
    it "does not trip the cap when resolution carries no user" do
      send_ai_notifications!(5)

      result = service.resolve(action_category: "widget.create")

      expect(result[:policy]).to eq("notify_and_proceed")
      expect(result[:notifications_suppressed]).to be_falsey
    end

    # Only notify_and_proceed rows consult the cap, so a row already sitting on
    # a stricter verb is not silently relaxed OR tightened by notification volume.
    it "leaves a require_approval row unchanged and unflagged over the cap" do
      relaxed_row.update!(policy: "require_approval")
      send_ai_notifications!(5)

      result = service.resolve(action_category: "widget.create", user: user)

      expect(result[:policy]).to eq("require_approval")
      expect(result[:channels]).to eq(%w[notification])
      expect(result[:notifications_suppressed]).to be_falsey
    end
  end
end
