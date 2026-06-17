# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Internal::Ai::RalphLoops scheduling", type: :request do
  include_context "internal api auth"

  let(:path) { "/api/v1/internal/ai/ralph_loops/process_scheduled" }

  def due_loop(account:)
    loop_record = create(:ai_ralph_loop, account: account, scheduling_mode: "autonomous",
                         status: "running", schedule_paused: false)
    # The autonomous next_scheduled_at callback normalizes the time to the next
    # cycle; force it into the past so the loop is due now (skip callbacks).
    loop_record.update_column(:next_scheduled_at, 1.minute.ago)
    loop_record
  end

  it "skips loops whose account has AI suspended (kill switch)" do
    due_loop(account: internal_account)
    allow_any_instance_of(Account).to receive(:ai_suspended?).and_return(true)

    post path, headers: service_headers

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body.dig("data", "loops_skipped")).to be >= 1
    expect(body.dig("data", "loops_processed")).to eq(0)
  end

  it "processes a due, non-suspended loop" do
    due_loop(account: internal_account)
    allow_any_instance_of(Account).to receive(:ai_suspended?).and_return(false)
    # Exercise scheduling, not a full agent run.
    allow_any_instance_of(Ai::Ralph::ExecutionService).to receive(:run_iteration).and_return({ success: true })

    post path, headers: service_headers

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body.dig("data", "loops_processed")).to be >= 1
  end
end
