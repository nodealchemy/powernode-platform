# frozen_string_literal: true

require "rails_helper"

# IMP-73dff8186c1e — Ai::AgentOutreachService is the ONE consumer for which the
# old "silent" resolution was already correct: a spent notification budget
# should stop the notification. Now that resolution keeps a real authorisation
# verb (require_approval) so gated WRITES are parked rather than refused, the
# delivery half of that decision arrives as `notifications_suppressed`, and this
# service is what has to honour it. Without that read, the fix would have traded
# a false 422 for a cap that silently stopped capping — note that
# `policy_result[:channels]` cannot carry the signal, because it arrives empty
# and `[].presence` is nil, so #notify's fallback would deliver anyway.
RSpec.describe Ai::AgentOutreachService do
  let(:account) { create(:account) }
  let(:user)    { create(:user, account: account) }
  let(:agent)   { create(:ai_agent, account: account) }
  let(:service) { described_class.new(account: account, agent: agent) }

  # #notify always passes an agent, so this row is scoped to it. A
  # scope-"global" row would bind here too — that is how
  # db/seeds/autonomy_data_seed.rb's status_update row reaches outreach
  # (IMP-cb36021d4094) — but a scope-"action_type" row would not: resolution
  # drops the operator audience for an agent caller.
  let!(:relaxed_row) do
    Ai::InterventionPolicy.create!(
      account: account, action_category: "status_update", scope: "agent",
      ai_agent_id: agent.id, policy: "notify_and_proceed", priority: 10,
      is_active: true, conditions: { "max_daily_notifications" => 2 }
    )
  end

  def notify!
    service.notify(user: user, type: "agent_status_update",
                   title: "Fleet update", message: "Two nodes reconciled")
  end

  # The cap counts this account's "ai"-category notifications for the day —
  # the same category #notify writes through Notification.create_for_user.
  def spend_budget!(count)
    count.times do
      create(:notification, account: account, user: user,
                            notification_type: "agent_status_update", category: "ai")
    end
  end

  it "delivers while the daily budget has headroom" do
    spend_budget!(1)

    result = nil
    expect { result = notify! }.to change { Notification.where(category: "ai").count }.by(1)
    expect(result[:delivered]).to be(true)
    expect(result[:channel]).to eq("notification")
  end

  it "writes no notification once the daily budget is spent" do
    spend_budget!(2)

    expect { notify! }.not_to change(Notification, :count)
  end

  it "reports the spent budget as the reason, distinct from a policy denial" do
    spend_budget!(2)

    result = notify!

    expect(result[:delivered]).to be(false)
    expect(result[:channel]).to be_nil
    expect(result[:reason]).to eq("notification_limit_reached")
  end

  # Positive twin for the branch above: a row whose stored verb IS "silent"
  # still suppresses on its own branch, and keeps its own reason. The cap path
  # must not absorb it — the two mean different things to an operator reading
  # the result back.
  it "still suppresses a policy whose verb is literally silent" do
    relaxed_row.update!(policy: "silent", conditions: {})

    result = nil
    expect { result = notify! }.not_to change(Notification, :count)
    expect(result[:reason]).to eq("silent_policy")
  end

  it "still reports a blocking policy as blocked rather than as a spent budget" do
    relaxed_row.update!(policy: "block", conditions: {})

    result = notify!

    expect(result[:delivered]).to be(false)
    expect(result[:reason]).to eq("blocked_by_policy")
  end

  # IMP-cb36021d4094 — the concrete production consequence of the audience cut,
  # asserted against the REAL seeded shape rather than a constructed fixture.
  #
  # db/seeds/autonomy_data_seed.rb seeds status_update at scope "global",
  # ai_agent_id nil, user_id nil, and its comment states why: without it
  # resolution "falls back to require_approval for all categories — which is
  # wrong for informational categories like status_update ... The LLM sees the
  # policy in the tool response and misinterprets it as a permission failure."
  #
  # #notify ALWAYS passes an agent (it is a required constructor argument), so
  # while the audience cut keyed on ai_agent_id, that row could never bind and
  # every agent outreach resolved to exactly the require_approval default the
  # seed exists to prevent. No agent-scoped row is present here, which is the
  # state of any category an operator has configured only account-wide.
  describe "against the seeded account-wide status_update row" do
    before { relaxed_row.destroy! }

    let!(:global_row) do
      Ai::InterventionPolicy.create!(
        account: account, action_category: "status_update", scope: "global",
        ai_agent_id: nil, user_id: nil, policy: "notify_and_proceed",
        priority: 0, is_active: true, preferred_channels: %w[notification]
      )
    end

    it "binds the account-wide row instead of the require_approval default" do
      result = notify!

      expect(result[:policy_result][:record]).to eq(global_row),
                                                 "the seeded account-wide row did not reach an agent outreach"
      expect(result[:policy_result][:policy]).to eq("notify_and_proceed"),
                                                 "outreach resolved the default the seed exists to prevent"
    end

    # The observable half, and the reason this is worth an assertion rather than
    # prose: #notify picks its delivery channel from `policy_result[:channels]`.
    # An unbound row means default_policy's %w[notification] is used, so an
    # operator who configured workspace delivery account-wide silently kept
    # getting notifications — a wrong-channel delivery, not a missing one, which
    # is why nothing surfaced it.
    it "delivers through the channel the account-wide row configures" do
      global_row.update!(preferred_channels: %w[workspace])

      result = nil
      expect { result = notify! }.not_to change { Notification.where(category: "ai").count }
      expect(result[:channel]).to eq("workspace"),
                                  "the account-wide row's preferred_channels were discarded for the default"
      expect(result[:delivered]).to be(true)
    end
  end

  # IMP-34beef811fdf — a notification VOLUME budget must never withhold a
  # CRITICAL notification. Resolution already carries that principle for the
  # stored verb (`severity == "critical" && best.policy == "silent"` returns
  # require_approval WITH channels, which #notify delivers), and the cap branch
  # sitting immediately below it disagreed: it set `notifications_suppressed`
  # without consulting severity, and #notify honours that flag before it
  # reaches a channel.
  #
  # Both directions are load-bearing. A "fix" that merely stopped capping would
  # satisfy the first example and destroy the budget, so the second is an
  # oracle and not decoration.
  describe "a critical notification against an exhausted daily budget" do
    it "still delivers" do
      spend_budget!(2)

      result = nil
      expect do
        result = service.notify(user: user, type: "agent_issue_detected",
                                title: "Node unreachable", message: "ops-hub stopped answering",
                                severity: "error", priority: 3, policy_severity: "critical")
      end.to change { Notification.where(category: "ai").count }.by(1)

      expect(result[:delivered]).to be(true)
      expect(result[:channel]).to eq("notification")
    end

    it "still suppresses a non-critical notification against the same budget" do
      spend_budget!(2)

      result = nil
      expect do
        result = service.notify(user: user, type: "agent_status_update",
                                title: "Fleet update", message: "Two nodes reconciled",
                                severity: "warning")
      end.not_to change(Notification, :count)

      expect(result[:delivered]).to be(false)
      expect(result[:reason]).to eq("notification_limit_reached")
    end
  end

  # The shape the finding actually names. #notify_escalation renders a critical
  # escalation into the NOTIFICATION severity vocabulary ("error"), not the
  # policy vocabulary ("critical"), so the criticality of the event has to
  # survive that translation or the exemption above never reaches the one
  # caller that most needs it.
  describe "#notify_escalation against an exhausted daily budget" do
    def escalation!(severity)
      Ai::AgentEscalation.create!(
        account: account, ai_agent_id: agent.id, escalated_to_user: user,
        escalation_type: "error", severity: severity, title: "Agent stuck mid-deploy"
      )
    end

    it "delivers a critical escalation" do
      escalation = escalation!("critical")
      spend_budget!(2)

      result = nil
      expect { result = service.notify_escalation(escalation: escalation) }
        .to change { Notification.where(category: "ai").count }.by(1)

      expect(result[:delivered]).to be(true)
    end

    it "still suppresses a low-severity escalation" do
      escalation = escalation!("low")
      spend_budget!(2)

      result = nil
      expect { result = service.notify_escalation(escalation: escalation) }
        .not_to change(Notification, :count)

      expect(result[:delivered]).to be(false)
      expect(result[:reason]).to eq("notification_limit_reached")
    end
  end

  # IMP-34beef811fdf, governance guard. Criticality must be DECLARED by the
  # producer, never inferred from the rendered notification severity.
  #
  # "error" is not a synonym for "critical" across this service's callers. It
  # is that for #notify_escalation and Ai::Tools::AgentAutonomyTool#report_issue,
  # which both write `x == "critical" ? "error" : "warning"` — but
  # #send_proactive_notification forwards `params["severity"]` verbatim, and its
  # tool schema documents the enum as "info, warning, error". There "error" is
  # the AGENT'S OWN top-of-enum choice for a routine notification.
  #
  # Inferring criticality from that word would hand an LLM-driven caller a way
  # to defeat the two controls an operator has over it: the volume budget and a
  # `silent` policy. Both directions are pinned here because both are one-line
  # regressions away.
  describe "an agent-chosen notification severity" do
    it "does not buy exemption from the daily budget" do
      spend_budget!(2)

      result = nil
      expect do
        result = service.notify(user: user, type: "agent_status_update",
                                title: "Routine sweep", message: "Nothing to report",
                                severity: "error")
      end.not_to change(Notification, :count)

      expect(result[:delivered]).to be(false)
      expect(result[:reason]).to eq("notification_limit_reached")
    end

    it "does not buy exemption from the daily budget when the agent writes \"critical\"" do
      spend_budget!(2)

      result = nil
      expect do
        result = service.notify(user: user, type: "agent_status_update",
                                title: "Routine sweep", message: "Nothing to report",
                                severity: "critical")
      end.not_to change(Notification, :count)

      expect(result[:delivered]).to be(false)
      expect(result[:reason]).to eq("notification_limit_reached")
    end

    it "does not override an operator's silent policy when the agent writes \"critical\"" do
      relaxed_row.update!(policy: "silent", conditions: {})

      result = nil
      expect do
        result = service.notify(user: user, type: "agent_status_update",
                                title: "Routine sweep", message: "Nothing to report",
                                severity: "critical")
      end.not_to change(Notification, :count)

      expect(result[:delivered]).to be(false)
      expect(result[:reason]).to eq("silent_policy")
    end

    it "does not override an operator's silent policy" do
      relaxed_row.update!(policy: "silent", conditions: {})

      result = nil
      expect do
        result = service.notify(user: user, type: "agent_status_update",
                                title: "Routine sweep", message: "Nothing to report",
                                severity: "error")
      end.not_to change(Notification, :count)

      expect(result[:delivered]).to be(false)
      expect(result[:reason]).to eq("silent_policy")
    end
  end

  # The counterpart, and the branch this change makes reachable for the first
  # time: a caller that DECLARES criticality overrides a silent row, which is
  # the stated intent of the severity override in
  # Ai::InterventionPolicyService#resolve. Before this change #notify_escalation
  # rendered a critical escalation as "error" and that override was dead for
  # every caller of this service.
  it "delivers a critical escalation over an operator's silent policy" do
    relaxed_row.update!(policy: "silent", conditions: {})
    escalation = Ai::AgentEscalation.create!(
      account: account, ai_agent_id: agent.id, escalated_to_user: user,
      escalation_type: "error", severity: "critical", title: "Agent stuck mid-deploy"
    )

    result = nil
    expect { result = service.notify_escalation(escalation: escalation) }
      .to change { Notification.where(category: "ai").count }.by(1)

    expect(result[:delivered]).to be(true)
  end
end
