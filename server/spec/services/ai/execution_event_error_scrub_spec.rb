# frozen_string_literal: true

require "rails_helper"

# IMP-dbabbea6f81c. Synthetic markers only.
RSpec.describe Ai::ExecutionEventErrorScrub do
  subject(:scrub) { described_class.new(sleeper: ->(_seconds) {}) }

  let(:account) { create(:account) }
  let(:secret) { %w[hunter 2].join }

  def event!(event_type:, error_message:)
    Ai::ExecutionEvent.create!(
      account: account, source_type: "Ai::ApprovalRequest", source_id: SecureRandom.uuid,
      event_type: event_type, status: "failed", error_message: error_message
    )
  end

  let!(:dirty)  { event!(event_type: "approval_execution", error_message: "login failed password=#{secret}") }
  let!(:clean)  { event!(event_type: "approval_execution", error_message: "provider timeout") }
  let!(:nil_msg) { event!(event_type: "approval_execution", error_message: nil) }
  let!(:other)  { event!(event_type: "other_event", error_message: "login failed password=#{secret}") }

  def run_quietly = scrub.call

  it "rewrites the stored approval_execution row through filter_text" do
    run_quietly

    expect(dirty.reload.error_message).to eq("login failed password=#{Ai::SensitiveParams::MASK}")
  end

  it "leaves clean, nil and other-event-type rows untouched" do
    run_quietly

    expect(clean.reload.error_message).to eq("provider timeout")
    expect(nil_msg.reload.error_message).to be_nil
    expect(other.reload.error_message).to include(secret)
  end

  it "leaves no dirty approval_execution row behind" do
    extra = Array.new(3) { event!(event_type: "approval_execution", error_message: "x password=#{secret} y") }

    result = run_quietly

    remaining = Ai::ExecutionEvent.where(event_type: "approval_execution").where("error_message LIKE ?", "%#{secret}%")
    expect(remaining).to be_empty
    expect(extra.map { |e| e.reload.error_message }).to all(include(Ai::SensitiveParams::MASK))
    expect(result.scrubbed).to eq(4)
    expect(result).to be_complete
  end

  it "is idempotent: a second run rewrites nothing" do
    run_quietly

    expect(scrub.call.scrubbed).to eq(0)
  end

  it "backs off on a lock timeout or deadlock, then skips the batch with its row count instead of raising" do
    pauses = []
    patient = described_class.new(sleeper: ->(seconds) { pauses << seconds })
    calls = 0
    allow(patient).to receive(:lock_and_scrub) do
      calls += 1
      raise(calls.odd? ? ActiveRecord::LockWaitTimeout : ActiveRecord::Deadlocked)
    end

    result = patient.call

    expect(calls).to eq(described_class::LOCK_ATTEMPTS)
    expect(pauses.size).to eq(described_class::LOCK_ATTEMPTS - 1)
    expect(result.scrubbed).to eq(0)
    expect(result.skipped_rows).to eq(2)
    expect(result).not_to be_complete
  end
end

# A real PG lock_timeout (55P03) held by another connection, not a stub: proves
# the adapter maps it to ActiveRecord::LockWaitTimeout. Needs COMMITTED rows
# (the holder is a second connection), so this group opts out of the wrapping
# test transaction and cleans up after itself.
RSpec.describe Ai::ExecutionEventErrorScrub, "against a real row lock" do
  self.use_transactional_tests = false

  let(:secret) { %w[hunter 2].join }
  let!(:account) { create(:account) }
  let!(:row) do
    Ai::ExecutionEvent.create!(account: account, source_type: "Ai::ApprovalRequest", source_id: SecureRandom.uuid,
                               event_type: "approval_execution", status: "failed",
                               error_message: "x password=#{secret}")
  end

  after do
    Ai::ExecutionEvent.where(id: row.id).delete_all
    Account.where(id: account.id).delete_all
  end

  it "maps a real PG lock_timeout to LockWaitTimeout and skips the locked batch" do
    holder = ActiveRecord::Base.connection_pool.checkout
    begin
      holder.execute("BEGIN")
      holder.execute("SELECT 1 FROM ai_execution_events WHERE id = '#{row.id}' FOR UPDATE")

      impatient = described_class.new(lock_timeout: "100ms", sleeper: ->(_seconds) {})
      expect { impatient.send(:lock_and_scrub, [ row.id ]) }.to raise_error(ActiveRecord::LockWaitTimeout)

      result = impatient.call
      expect(result.skipped_rows).to eq(1)
      expect(row.reload.error_message).to include(secret)
    ensure
      holder.execute("ROLLBACK")
      ActiveRecord::Base.connection_pool.checkin(holder)
    end

    expect(described_class.new.call.scrubbed).to eq(1)
  end
end
