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
                     priority: 5, conditions: {}, user_id: nil,
                     action_category: "widget.create")
    Ai::InterventionPolicy.create!(
      account: account,
      scope: scope,
      action_category: action_category,
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

  # IMP-6430e3a8c4a1 — the specificity hierarchy is LEXICOGRAPHIC, and `priority`
  # breaks ties WITHIN a tier rather than across them.
  #
  # A regression introduced by IMP-cb36021d4094. That fix correctly restored
  # scope-"global" rows to the agent pool, but the code it replaced also gave an
  # agent's own rows HARD precedence (`matching = agent_scoped if
  # agent_scoped.any?`). With that gone the winner was decided by `max_by` over
  # an ADDITIVE score — user +10, agent +5, specific category +2, then
  # `+ priority`. `priority` is operator-settable and unbounded, so it did not
  # break ties inside the hierarchy, it outranked the whole of it.
  #
  # Concrete fail-OPEN: a scope-"global" auto_approve at priority 10 scored 12
  # and beat an agent's own explicit require_approval at priority 0, which
  # scored 7 — an action the operator gated for that specific agent proceeded
  # unattended. Note the shape: the operator's INTENT was more restrictive and
  # was silently discarded, so a stricter row was the one that lost.
  #
  # Re-weighting cannot fix this. Any constant large enough to outrank "plausible"
  # priorities is the same defect with a bigger number, and fails the first time
  # an operator sets a priority above it. The tiers are therefore compared
  # element-by-element and `priority` sits in the LAST element, where no value it
  # can take reaches a tier above it.
  describe "#resolve precedence: tiers dominate priority (IMP-6430e3a8c4a1)" do
    let(:user) { create(:user, account: account) }

    # 1. THE FIX — red before it. Priority 10 vs 0 is a realistic operator gap
    #    (the seeds already span 0..10), not a contrived one.
    it "keeps an agent's own require_approval above a higher-priority global auto_approve" do
      create_policy!(policy: "auto_approve", scope: "global", priority: 10)
      own = create_policy!(policy: "require_approval", scope: "agent",
                           ai_agent_id: agent.id, priority: 0)

      result = service.resolve(action_category: "widget.create", agent: agent)

      expect(result[:record]).to eq(own),
                                 "a global row outranked the agent's own row on priority alone — fail-OPEN"
      expect(result[:policy]).to eq("require_approval")
    end

    # 2. The documented order in #resolve's docstring, asserted across a RANGE of
    #    priorities rather than one pair — every row here carries a priority that
    #    inverts the tier it sits in, so the additive score ranks them in exactly
    #    the reverse of the contract. Each tier is checked by destroying the
    #    current winner and re-resolving, so all four positions are pinned in one
    #    example instead of only the top one.
    #
    #    The audience filter is why each tier is seeded at the scope it is: for an
    #    agent caller only that agent's own rows and scope-"global" rows are
    #    admitted (IMP-cb36021d4094), so the two agent-less tiers must be global.
    it "holds user+agent > user > agent > global against priorities that invert the tiers" do
      global_row = create_policy!(policy: "silent", scope: "global", priority: 30)
      agent_row  = create_policy!(policy: "notify_and_proceed", scope: "agent",
                                  ai_agent_id: agent.id, priority: 20)
      user_row   = create_policy!(policy: "auto_approve", scope: "global",
                                  user_id: user.id, priority: 10)
      both_row   = create_policy!(policy: "block", scope: "agent",
                                  ai_agent_id: agent.id, user_id: user.id, priority: 0)

      resolved = [both_row, user_row, agent_row].map do |winner|
        record = service.resolve(action_category: "widget.create", agent: agent, user: user)[:record]
        winner.destroy!
        record
      end
      resolved << service.resolve(action_category: "widget.create", agent: agent, user: user)[:record]

      expect(resolved).to eq([both_row, user_row, agent_row, global_row])
    end

    # 3. CONTROL — `priority` is the operator's ONLY ordering lever, and the fix
    #    must not remove it. Two rows in the same tier, decided by priority alone.
    #
    #    The `resolve` half of this example CANNOT fail: `#resolve` enumerates
    #    `by_specificity`, which is `order(priority: :desc)`, and `max_by` keeps
    #    the FIRST of equal keys — so with `priority` deleted from the key
    #    entirely the query order alone still returns the higher-priority row.
    #    Measured, not reasoned: the mutant that drops that element survives the
    #    resolve assertion and dies only on the key comparison below. No
    #    behavioural example through `resolve` can separate the two, because the
    #    confounder IS the intended answer. Hence the direct comparison, which is
    #    independent of enumeration order and is what actually pins the lever.
    it "still lets priority decide between two rows in the same tier" do
      quieter = create_policy!(policy: "block", scope: "global", priority: 0)
      louder  = create_policy!(policy: "auto_approve", scope: "global", priority: 10)

      expect(quieter.specificity_key <=> louder.specificity_key).to eq(-1),
                                                                   "priority stopped ordering rows within a tier — the operator's only lever is gone"

      result = service.resolve(action_category: "widget.create", agent: agent)

      expect(result[:record]).to eq(louder)
      expect(result[:policy]).to eq("auto_approve")
    end

    # 3b. CONTROL, and the SEEDED shape of that lever. Both rows are agent-less
    #     with no user, so they share a tier, and the only thing separating them
    #     is priority: System::Seeds::AgentSetupHelpers.upsert_operator_policies!
    #     writes scope "action_type" at priority 5, while
    #     db/seeds/autonomy_data_seed.rb writes scope "global" at priority 0.
    #     Nothing else in the tree relies on cross-tier priority ordering.
    #
    #     Carries the same confounder as assertion 3 — the query order would
    #     produce this answer even with `priority` out of the key — so it pins
    #     the seeded OUTCOME, and assertion 3's key comparison pins the mechanism.
    it "keeps the seeded operator row (action_type, priority 5) above the global floor (priority 0)" do
      create_policy!(policy: "auto_approve", scope: "global", priority: 0)
      operator = create_policy!(policy: "require_approval", scope: "action_type", priority: 5)

      result = service.resolve(action_category: "widget.create", agent: nil, user: user)

      expect(result[:record]).to eq(operator)
      expect(result[:policy]).to eq("require_approval")
    end

    # 4. CONTROL — the operator-path separation from IMP-cb36021d4094, restated
    #    at a priority no re-weighting could survive.
    #
    #    This example CANNOT detect readmission of the operator audience, despite
    #    its name. Measured against a mutant that deletes the audience cut
    #    entirely: the action_type row is then admitted and ranked, but it ranks
    #    `[0, 0, 1, 99]` against the agent's own `[0, 1, 1, 0]` and still loses,
    #    so this example stays green. It is assertion 1 with `scope:` changed,
    #    and it pins only that a large priority on an operator row cannot win.
    #    4b below is what actually holds the separation — that same mutant reds
    #    it, along with four IMP-cb36021d4094/bfbf8052e179 examples above.
    it "still keeps a scope-action_type row away from an agent caller at any priority" do
      create_policy!(policy: "auto_approve", scope: "action_type", priority: 99)
      own = create_policy!(policy: "require_approval", scope: "agent",
                           ai_agent_id: agent.id, priority: 0)

      result = service.resolve(action_category: "widget.create", agent: agent)

      expect(result[:record]).to eq(own),
                                 "an operator-path row re-entered the agent pool (IMP-cb36021d4094 regressed)"
      expect(result[:policy]).to eq("require_approval")
    end

    # 4b. The sharper half of the same control: with no row of its own the agent
    #     must fall to the require_approval DEFAULT, never catch the operator row.
    #     Assertion 4 alone is satisfied by an ordering that admits the operator
    #     row but ranks it below the agent's; this one is not.
    it "falls to the default rather than an action_type row when the agent has no row of its own" do
      create_policy!(policy: "auto_approve", scope: "action_type", priority: 99)

      result = service.resolve(action_category: "widget.create", agent: agent)

      expect(result[:policy]).to eq("require_approval")
      expect(result[:record]).to be_nil,
                                 "an operator-path row bound an agent with no row of its own"
    end

    # 4c. STRUCTURAL, and the only assertion here that a re-weighting cannot
    #     survive. Every behavioural example above is satisfied by an additive
    #     score whose constants merely exceed the priorities it happens to use —
    #     which is the same defect with a bigger number, and fails the day an
    #     operator sets a priority above the constant. No finite example rules
    #     that out, because the constants can always be raised past it.
    #
    #     So assert the SHAPE instead: `priority` occupies exactly the last
    #     element and influences nothing else. An additive score moves with
    #     priority in every element it has, so its three samples are three
    #     distinct values and `uniq.length` is 3; a key that folds priority into
    #     a tier element fails the same way. Both die here at any constant.
    #
    #     (Not by raising, note — `Integer#[]` takes a Range in Ruby 3.x, so a
    #     scalar score answers `12[0..-2] #=> 12` rather than NoMethodError. The
    #     example is sound; it is the uniqueness check that kills, not a type
    #     error.)
    it "confines priority to the last element of the key, leaving the tiers invariant" do
      row  = create_policy!(policy: "block", scope: "agent", ai_agent_id: agent.id, priority: 0)
      keys = [0, 1_000, 2_147_483_647].map { |p| row.priority = p; row.specificity_key }

      expect(keys.map { |k| k[0..-2] }.uniq.length).to eq(1),
                                                       "a tier element moved with priority — the key is a re-weighted score, not lexicographic"
      expect(keys.map(&:last)).to eq([0, 1_000, 2_147_483_647])
    end

    # 4d. The behavioural twin of 4c, at the largest priority the int4 column can
    #     hold. A re-weighting survives this only with constants above 2^31.
    it "keeps the agent tier above a global row at the maximum storable priority" do
      create_policy!(policy: "auto_approve", scope: "global", priority: 2_147_483_647)
      own = create_policy!(policy: "require_approval", scope: "agent",
                           ai_agent_id: agent.id, priority: 0)

      result = service.resolve(action_category: "widget.create", agent: agent)

      expect(result[:record]).to eq(own)
      expect(result[:policy]).to eq("require_approval")
    end

    # 5. Category specificity is the same defect one dimension down: it was worth
    #    +2 against an unbounded `priority`, so a wildcard row outranked a row
    #    naming the category from priority 3 upward. It sits above `priority` in
    #    the key for the same reason the scope tiers do. No seed writes a
    #    wildcard row today, so this changes no seeded outcome.
    it "keeps a specific-category row above a wildcard row carrying a higher priority" do
      create_policy!(policy: "auto_approve", scope: "global", priority: 50, action_category: "*")
      specific = create_policy!(policy: "require_approval", scope: "global", priority: 0)

      result = service.resolve(action_category: "widget.create", agent: agent)

      expect(result[:record]).to eq(specific)
      expect(result[:policy]).to eq("require_approval")
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

    # IMP-34beef811fdf — the cap branch sat directly beneath an override whose
    # whole stated intent is that a critical event never resolves silently, and
    # disagreed with it: it set `notifications_suppressed` without consulting
    # `severity`, and Ai::AgentOutreachService#notify returns delivered:false on
    # that flag before it reaches a channel. A volume budget may reduce routine
    # chatter; it may never withhold a critical notification.
    #
    # Asserted on the PRODUCER because that is where the fix lives: the flag is
    # unexpressible for a critical severity, so a consumer cannot re-create the
    # inversion by forgetting to re-check.
    context "when the event is critical" do
      it "never reports the delivery as suppressed" do
        send_ai_notifications!(5)

        result = service.resolve(action_category: "widget.create", user: user, severity: "critical")

        expect(result[:notifications_suppressed]).to be_falsey
      end

      it "returns audible channels rather than the empty suppression array" do
        send_ai_notifications!(5)

        result = service.resolve(action_category: "widget.create", user: user, severity: "critical")

        expect(result[:channels]).to eq(%w[notification])
      end

      it "honours the row's own preferred channels" do
        relaxed_row.update!(preferred_channels: %w[workspace])
        send_ai_notifications!(5)

        result = service.resolve(action_category: "widget.create", user: user, severity: "critical")

        expect(result[:channels]).to eq(%w[workspace])
      end

      # The exemption is DELIVERY-only. IMP-73dff8186c1e's authorisation
      # contract — the cap parks a gated write rather than refusing it — is
      # unchanged for every severity, so a critical event over the cap is still
      # a require_approval and still never a denial verb.
      it "still degrades the verb to require_approval" do
        send_ai_notifications!(5)

        result = service.resolve(action_category: "widget.create", user: user, severity: "critical")

        expect(result[:policy]).to eq("require_approval")
        expect(result[:policy]).not_to be_in(%w[silent block])
        expect(result[:reason]).to match(/Daily notification limit reached/)
      end

      # The operator preview endpoint
      # (Api::V1::Ai::InterventionPoliciesController#resolve) renders this
      # hash verbatim, so the reason has to say which of the two things
      # happened rather than leave "limit reached" sitting next to audible
      # channels.
      it "says the limit was reached WITHOUT suppressing" do
        send_ai_notifications!(5)

        result = service.resolve(action_category: "widget.create", user: user, severity: "critical")

        expect(result[:reason]).to eq(
          "Daily notification limit reached (critical severity exempt from suppression)"
        )
      end

      # The budget must keep working, or the fix would just be a disabled cap.
      it "leaves a non-critical event suppressed under the same exhausted cap" do
        send_ai_notifications!(5)

        # "error" is deliberately in this list. It is a NOTIFICATION severity,
        # not a policy one, and resolution must not learn to read it as
        # critical: Ai::AgentOutreachService callers DECLARE criticality via
        # `policy_severity`, precisely so that an agent choosing "error" for
        # its own routine traffic cannot exempt itself from an operator's cap.
        %w[info warning error].each do |severity|
          result = service.resolve(action_category: "widget.create", user: user, severity: severity)

          expect(result[:notifications_suppressed]).to be(true), "#{severity} escaped the cap"
          expect(result[:channels]).to eq([])
        end
      end
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

  # IMP-e75e843bd42b — the cap's COUNT excludes approval consent traffic.
  #
  # Exhausting the cap degrades the verb to require_approval; parking then
  # emits one category-"ai" approval notification per approver (the default
  # chain's ["*"] resolves to EVERY active user), and those rows fed straight
  # back into notification_limit_reached?'s count. The budget cannot suppress
  # them — Ai::ApprovalRequestNotifier never consults it — so an exhausted
  # budget INFLATED ITSELF with traffic it has no lever over, and ordinary
  # consent activity under the (default!) require_approval policy burned the
  # outreach budget of users who had received no outreach at all.
  #
  # DECIDED: consent traffic is neither counted toward nor throttled by the
  # budget. The discriminator is the `approval_request_id` metadata key, which
  # Ai::ApprovalRequestNotifier#notify_current_step! writes unconditionally at
  # the single fan-out site — producer-declared, independent of the pluggable
  # content handler's notification_type.
  describe "#resolve approval fan-out excluded from the counted budget (IMP-e75e843bd42b)" do
    let(:user) { create(:user, account: account) }

    let!(:relaxed_row) do
      create_policy!(policy: "notify_and_proceed",
                     conditions: { "max_daily_notifications" => 2 })
    end

    def send_approval_notifications!(count)
      count.times do
        create(:notification, account: account, user: user,
                              notification_type: "autonomy_approval_required", category: "ai",
                              metadata: { "approval_request_id" => SecureRandom.uuid })
      end
    end

    def send_outreach_notifications!(count)
      count.times do
        create(:notification, account: account, user: user,
                              notification_type: "agent_status_update", category: "ai")
      end
    end

    it "does not count approval fan-out notifications toward the budget" do
      send_approval_notifications!(3)

      result = service.resolve(action_category: "widget.create", user: user)

      expect(result[:policy]).to eq("notify_and_proceed")
      expect(result[:notifications_suppressed]).to be_falsey
    end

    # Positive control: the exclusion must not disable the cap. Outreach
    # traffic — no approval_request_id key — still counts and still degrades.
    it "still counts outreach notifications and degrades once they reach the cap" do
      send_outreach_notifications!(2)

      result = service.resolve(action_category: "widget.create", user: user)

      expect(result[:policy]).to eq("require_approval")
      expect(result[:notifications_suppressed]).to be(true)
    end

    # Mixed day: only the outreach rows count. 1 outreach + 3 approval rows
    # against a cap of 2 leaves headroom.
    it "counts only the outreach share of a mixed day" do
      send_outreach_notifications!(1)
      send_approval_notifications!(3)

      result = service.resolve(action_category: "widget.create", user: user)

      expect(result[:policy]).to eq("notify_and_proceed")
      expect(result[:notifications_suppressed]).to be_falsey
    end

    # The measured amplification, end-to-end through the REAL fan-out
    # (Ai::ApprovalRequest after_create → Ai::ApprovalRequestNotifier), on a
    # step whose approvers are ["*"] exactly like the default chain
    # Ai::AutonomyGate#resolve_chain builds:
    #
    #   1. one parked write emits one category-"ai" notification per ACTIVE
    #      USER in the account — the fan-out width the filing asked to have
    #      measured;
    #   2. every one of those rows carries the `approval_request_id` metadata
    #      key — the premise the count exclusion above stands on, pinned
    #      against the producer so a notifier refactor that drops the key
    #      fails HERE and not silently in the count;
    #   3. the fan-out does not consume the recipients' outreach budget: a
    #      user whose day held nothing but consent traffic still resolves
    #      notify_and_proceed. Before this fix the same resolve degraded —
    #      the exhausted path inflating the very count that exhausts it.
    it "one parked write fans out to every active user without consuming their outreach budget" do
      relaxed_row.update!(conditions: { "max_daily_notifications" => 1 })
      others = create_list(:user, 3, account: account)
      approvers = [ user ] + others

      expect {
        create(:ai_approval_request, account: account, requested_by: user)
      }.to change { Notification.where(account_id: account.id).count }.by(approvers.size)

      fan_out = Notification.where(account_id: account.id, user_id: approvers.map(&:id))
      expect(fan_out.count).to eq(approvers.size)
      expect(fan_out.pluck(:category).uniq).to eq([ "ai" ])
      expect(fan_out.map { |n| n.metadata["approval_request_id"] }).to all(be_present)

      result = service.resolve(action_category: "widget.create", user: user)

      expect(result[:policy]).to eq("notify_and_proceed")
      expect(result[:notifications_suppressed]).to be_falsey
    end

    # Composition with IMP-34beef811fdf: nothing here adds a suppression path.
    # Approval fan-out has NO suppression path at all (the notifier never
    # reads the flag or the cap), and the producer-side critical exemption is
    # untouched — over a cap genuinely exhausted by outreach, a critical
    # event still cannot express notifications_suppressed: true.
    it "leaves the critical exemption intact over a cap exhausted by outreach" do
      send_outreach_notifications!(5)
      send_approval_notifications!(2)

      result = service.resolve(action_category: "widget.create", user: user, severity: "critical")

      expect(result[:policy]).to eq("require_approval")
      expect(result[:notifications_suppressed]).to be_falsey
      expect(result[:channels]).to eq(%w[notification])
    end
  end

  # IMP-e43194754178 — the predicate arms of the exhausted cap.
  #
  # Ai::Autonomy::ExecutionGateService consumes resolution ONLY through these
  # two predicates (#check_intervention_policy: auto_approve? to promote a
  # requires_approval to :proceed, blocked? to deny), and it passes `agent:`
  # and `user:` on both calls — so both are cap-reachable call sites. They
  # are inert over the cap by construction: the cap branch returns
  # "require_approval", which satisfies neither `== "block"` nor
  # `== "auto_approve"`. That inertness IS the contract being pinned — if the
  # cap branch ever degraded to "block", ExecutionGateService would silently
  # start folding a spent notification budget into a denial, the exact
  # inversion IMP-73dff8186c1e removed from the other consumers.
  #
  # These examples assert already-correct behaviour, so they cannot be
  # red-first; non-vacuity is carried by mutation instead (returning "block"
  # from the cap branch must redden the blocked? example below) plus the
  # positive anchors, which show the same call shape flipping on the real
  # verbs.
  describe "#blocked? / #auto_approve? under an exhausted cap (IMP-e43194754178)" do
    let(:user) { create(:user, account: account) }

    # scope "global" — the one audience that binds an agent+user caller, and
    # the shape db/seeds/autonomy_data_seed.rb actually seeds.
    let!(:relaxed_row) do
      create_policy!(policy: "notify_and_proceed", scope: "global",
                     conditions: { "max_daily_notifications" => 1 })
    end

    before do
      create(:notification, account: account, user: user,
                            notification_type: "agent_status_update", category: "ai")
    end

    it "keeps blocked? false while the cap degrades the verb" do
      # Premise guard: the CAP branch specifically is live for this exact call
      # shape — `reason` and `record` distinguish it from default_policy, which
      # also answers "require_approval" but matches no row.
      result = service.resolve(action_category: "widget.create", agent: agent, user: user)
      expect(result[:policy]).to eq("require_approval")
      expect(result[:reason]).to match(/Daily notification limit reached/)
      expect(result[:record]).to eq(relaxed_row)

      expect(service.blocked?(action_category: "widget.create", agent: agent, user: user)).to be(false)
    end

    it "keeps auto_approve? false while the cap degrades the verb" do
      result = service.resolve(action_category: "widget.create", agent: agent, user: user)
      expect(result[:policy]).to eq("require_approval")
      expect(result[:reason]).to match(/Daily notification limit reached/)
      expect(result[:record]).to eq(relaxed_row)

      expect(service.auto_approve?(action_category: "widget.create", agent: agent, user: user)).to be(false)
    end

    # Anchors: the same predicates on the same call shape DO flip on the real
    # verbs, so the falses above are read off the resolution, not vacuous.
    it "still reports blocked? true for a genuine block row" do
      relaxed_row.update!(policy: "block")

      expect(service.blocked?(action_category: "widget.create", agent: agent, user: user)).to be(true)
    end

    it "still reports auto_approve? true for a genuine auto_approve row" do
      relaxed_row.update!(policy: "auto_approve")

      expect(service.auto_approve?(action_category: "widget.create", agent: agent, user: user)).to be(true)
    end
  end
end
