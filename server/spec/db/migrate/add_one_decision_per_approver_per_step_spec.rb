# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db", "migrate", "20260911045828_add_one_decision_per_approver_per_step_to_ai_approval_decisions.rb")

# The index migration must never touch a decision row: duplicates are audit
# evidence. With any present it stops and names the count; with none it adds
# the unique index.
RSpec.describe AddOneDecisionPerApproverPerStepToAiApprovalDecisions, type: :migration do
  let(:migration) { described_class.new }
  let(:connection) { ActiveRecord::Base.connection }
  let(:index_name) { described_class::INDEX_NAME }

  around { |example| ActiveRecord::Migration.suppress_messages { example.run } }
  # Real DDL runs inside each example; the example's transaction rolls it back,
  # and the plan cache is dropped after the file (spec/lint/migration_spec_plan_cache_spec.rb).
  after(:context) { ActiveRecord::Base.connection.clear_cache! }

  before { migration.down if connection.index_name_exists?(:ai_approval_decisions, index_name) }

  def index_present?
    connection.index_name_exists?(:ai_approval_decisions, index_name)
  end

  it "stops and names the count when duplicate decisions exist, and changes none of them" do
    request = create(:ai_approval_request)
    approver = create(:user, account: request.account)
    2.times do
      Ai::ApprovalDecision.create!(approval_request: request, approver: approver, step_number: 0, decision: "approved")
    end

    expect { migration.up }.to raise_error(ActiveRecord::MigrationError, /\b1 \(approval request, step, approver\) group\(s\)/)
    expect(Ai::ApprovalDecision.where(approval_request_id: request.id).count).to eq(2)
    expect(index_present?).to be(false)
  end

  it "adds the unique index when there are none" do
    migration.up

    index = connection.indexes(:ai_approval_decisions).find { |candidate| candidate.name == index_name }
    expect(index).to be_present
    expect(index.unique).to be(true)
    expect(index.columns).to eq(%w[approval_request_id step_number approver_id])
  end
end
