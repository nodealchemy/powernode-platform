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
end
