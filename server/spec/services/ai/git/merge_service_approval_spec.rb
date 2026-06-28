# frozen_string_literal: true

require "rails_helper"

# Regression: approve_merge! must actually merge. Previously execute() always
# re-ran the static branch-protection check, so after approve_merge! set
# merge_approved_by the re-execute re-gated and the merge never happened (the
# auto-land approval gate could never complete). The fix lets execute() treat a
# present merge_approved_by as satisfying the approval requirement.
RSpec.describe Ai::Git::MergeService do
  let(:session) { create(:ai_worktree_session, merge_strategy: "sequential") }
  let(:service) { described_class.new(session: session) }

  before do
    allow(service).to receive(:branch_protection_service).and_return(
      double(validate_merge_target: { requires_approval: true, message: "develop is protected" })
    )
  end

  it "gates a protected target on first execute" do
    result = service.execute
    expect(result).to include(requires_approval: true)
    expect(session.reload.metadata["awaiting_merge_approval"]).to be(true)
  end

  it "actually performs the merge after approve_merge! (no re-gate loop)" do
    service.execute # establishes the pending approval
    allow(service).to receive(:execute_sequential).and_return({ success: true, merged: 1 })

    result = service.approve_merge!(approved_by: "user-1")

    expect(result).to include(success: true, merged: 1)
    expect(session.reload.metadata["merge_approved_by"]).to eq("user-1")
  end
end
