# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261020140000_scrub_historical_execution_event_errors.rb")

# IMP-dbabbea6f81c. Synthetic markers only.
RSpec.describe ScrubHistoricalExecutionEventErrors do
  subject(:migration) { described_class.new }

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

  def run_quietly
    allow(migration).to receive(:say)
    migration.up
  end

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

  it "is idempotent: a second run rewrites nothing" do
    run_quietly

    expect(migration.up).to eq(0)
  end

  it "never prints what it redacts" do
    printed = []
    allow(migration).to receive(:say) { |msg| printed << msg }

    migration.up

    expect(printed.join).not_to include(secret)
    expect(printed).not_to be_empty
  end

  it "is irreversible" do
    expect { migration.down }.to raise_error(ActiveRecord::IrreversibleMigration)
  end
end
