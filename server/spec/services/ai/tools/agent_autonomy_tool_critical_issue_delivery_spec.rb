# frozen_string_literal: true

require "rails_helper"

# IMP-34beef811fdf — coverage for the third leg of the criticality fix.
#
# Ai::AgentOutreachService#notify reads ONLY the declared `policy_severity`;
# the rendered notification `severity` is never re-read as a policy severity.
# #report_issue renders a critical issue as "error" (the frontend has no
# "critical" notification severity), so it must DECLARE criticality or a
# critical issue report is withheld the moment the operator's daily
# notification budget is spent.
#
# This drives the real Ai::AgentOutreachService and a real policy row rather
# than stubbing the outreach, because the whole defect lived in the seam
# between the two.
RSpec.describe Ai::Tools::AgentAutonomyTool, "critical issue delivery over an exhausted budget" do
  let(:account) { create(:account) }
  let!(:owner)  { create(:user, :owner, account: account) }
  let(:agent)   { create(:ai_agent, account: account) }
  let(:tool)    { described_class.new(account: account, agent: agent, user: owner) }

  let!(:relaxed_row) do
    Ai::InterventionPolicy.create!(
      account: account, action_category: "status_update", scope: "agent",
      ai_agent_id: agent.id, policy: "notify_and_proceed", priority: 10,
      is_active: true, conditions: { "max_daily_notifications" => 2 }
    )
  end

  before do
    allow(Ai::Connectors::TrackerConfig).to receive(:enabled?).and_return(false)
    2.times do
      create(:notification, account: account, user: owner,
                            notification_type: "agent_status_update", category: "ai")
    end
  end

  def report!(severity)
    tool.send(:report_issue, { "title" => "Disk full", "description" => "ops-hub /persist at 100%",
                               "severity" => severity })
  end

  it "still notifies the owner of a critical issue" do
    expect { report!("critical") }
      .to change { Notification.where(category: "ai", notification_type: "agent_issue_detected").count }
      .by(1)
  end

  # The budget must keep working. A non-critical issue report over the same
  # spent budget stays suppressed, so the exemption is criticality and not a
  # disabled cap.
  it "still withholds a non-critical issue report" do
    expect { report!("warning") }.not_to change(Notification, :count)
  end

  # The notification keeps its RENDERED word. Storing a literal "critical"
  # would render the most urgent event with the INFO icon, because the
  # frontend's NotificationSeverity union has no "critical".
  it "renders the critical issue as an error-severity notification" do
    report!("critical")

    expect(Notification.where(notification_type: "agent_issue_detected").last.severity).to eq("error")
  end
end
