# frozen_string_literal: true

require "rails_helper"

# The one-off ops repair for lapses the hourly sweep recorded as "withdrawn"
# before "expired" existed: dry-run by default, APPLY=1 to change anything.
RSpec.describe Ai::AgentProposals::ExpiryBackfill do
  let(:account) { create(:account) }
  let(:agent) { create(:ai_agent, account: account, name: "Filer Agent") }

  def proposal(title:, status: "withdrawn", deadline: 3.days.ago, updated_at: 2.days.ago, reviewed_at: nil)
    row = account.ai_agent_proposals.create!(ai_agent_id: agent.id, title: title, proposal_type: "feature",
                                             priority: "low", review_deadline: deadline)
    row.update_columns(status: status, updated_at: updated_at, reviewed_at: reviewed_at)
    row
  end

  # A sweep lapse: withdrawn, no reviewer stamp, written after the deadline.
  let!(:lapses) { Array.new(5) { |i| proposal(title: "lapse #{i}") } }
  # The agent withdrew it BEFORE the deadline: a genuine withdrawal.
  let!(:own_withdrawal) { proposal(title: "own withdrawal", deadline: 1.day.from_now, updated_at: 1.hour.ago) }
  let!(:reviewed) { proposal(title: "reviewed", reviewed_at: 1.day.ago, status: "withdrawn") }
  let!(:pending) { proposal(title: "still pending", status: "pending_review") }

  it "selects only withdrawn rows with no reviewer stamp that were updated at or after their deadline" do
    expect(described_class.new.candidates.pluck(:id)).to match_array(lapses.map(&:id))
  end

  it "defaults to a dry run that changes nothing and writes no audit row" do
    report = described_class.new.run

    expect(report[:applied]).to be false
    expect(report[:count]).to eq(5)
    expect(lapses.map { |p| p.reload.status }.uniq).to eq(%w[withdrawn])
    expect(AuditLog.where(action: "ai.proposal.expired")).to be_empty
  end

  it "reports the count, first 3, last 1 and a full report of every withdrawn row" do
    out = StringIO.new
    described_class.new(io: out).run
    text = out.string

    expect(text).to include("This will affect 5")
    expect(text).to include("lapse 0", "lapse 1", "lapse 2", "lapse 4")
    expect(text).to include("Filer Agent")
    expect(text).to include("DRY RUN")
    full = text.split("ALL WITHDRAWN").last
    expect(full).to include("own withdrawal", "reviewed", "lapse 3")
    expect(full).not_to include("still pending")
  end

  it "applies only when told to, marking each expired and auditing it" do
    report = described_class.new(apply: true).run

    expect(report[:applied]).to be true
    expect(lapses.map { |p| p.reload.status }.uniq).to eq(%w[expired])
    expect(own_withdrawal.reload.status).to eq("withdrawn")
    expect(reviewed.reload.status).to eq("withdrawn")
    rows = AuditLog.where(action: "ai.proposal.expired", resource_type: "Ai::AgentProposal")
    expect(rows.count).to eq(5)
    expect(rows.first.metadata).to include("backfill" => true, "previous_status" => "withdrawn")
    expect(rows.pluck(:user_id).uniq).to eq([ nil ])
  end

  it "is a no-op the second time" do
    described_class.new(apply: true).run
    expect(described_class.new(apply: true).run[:count]).to eq(0)
  end
end
