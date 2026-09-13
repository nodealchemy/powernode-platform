# frozen_string_literal: true

require "rails_helper"

# A task parked for operator review (blocked_for "review") has no transition back
# to the queue: dev_next_task claims only pending tasks, dev_update_task cannot
# change status, and dev_complete_task only moves a task to a terminal or
# blocked state. So an operator's answer to the question that blocked it was
# recorded and never delivered. #requeue! is that missing transition.
RSpec.describe Ai::RalphTask, "#requeue!", type: :model do
  let(:task) do
    create(:ai_ralph_task, status: "blocked", error_message: "BLOCKED on a decision",
                           execution_attempts: 2,
                           metadata: { "blocked_for" => "review", "claimed_by" => "instance:abc",
                                       "claimed_holder" => "default", "claimed_at" => 1.hour.ago.iso8601,
                                       "operator_notes" => [ { "note" => "ruling" } ] })
  end

  it "returns a blocked task to the queue and clears the claim and the block" do
    task.requeue!(reason: "operator answered", by: "user:1")

    expect(task.reload.status).to eq("pending")
    expect(task.error_message).to be_nil
    expect(task.metadata.values_at("blocked_for", "claimed_by", "claimed_holder", "claimed_at")).to all(be_nil)
    expect(task.review_parked?).to be(false)
  end

  it "keeps what blocked it, who requeued it and why, and the notes and attempt count" do
    task.requeue!(reason: "operator answered", by: "user:1")

    history = task.reload.metadata["requeue_history"]
    expect(history.size).to eq(1)
    expect(history.first).to include("by" => "user:1", "reason" => "operator answered",
                                     "previous_error_message" => "BLOCKED on a decision",
                                     "previous_blocked_for" => "review", "previous_claimed_by" => "instance:abc")
    expect(task.metadata["operator_notes"]).to eq([ { "note" => "ruling" } ])
    expect(task.execution_attempts).to eq(2)
  end

  it "appends to the history on a second requeue" do
    task.requeue!(reason: "first", by: "user:1")
    task.update!(status: "blocked", error_message: "blocked again")

    task.requeue!(reason: "second", by: "user:2")

    expect(task.reload.metadata["requeue_history"].map { |h| h["reason"] }).to eq(%w[first second])
  end

  it "refuses a task that is not blocked" do
    %w[pending in_progress passed failed skipped].each do |status|
      other = create(:ai_ralph_task, status: status)

      expect { other.requeue!(reason: "x", by: "user:1") }
        .to raise_error(Ai::RalphTask::InvalidTransitionError), "#{status} was requeued"
      expect(other.reload.status).to eq(status)
    end
  end

  it "requires a reason" do
    expect { task.requeue!(reason: " ", by: "user:1") }.to raise_error(ArgumentError, /reason/)
    expect(task.reload.status).to eq("blocked")
  end
end
