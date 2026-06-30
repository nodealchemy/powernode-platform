# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::CodeFactory::PreflightGateService do
  let(:account) { create(:account) }
  let(:changed_files) { ["server/app/core_engine/x.rb"] }

  def build_contract(merge_policy: {})
    Ai::CodeFactory::RiskContract.create!(
      account: account, name: "c", status: "active",
      merge_policy: merge_policy,
      risk_tiers: [{ "tier" => "critical", "patterns" => ["**/core_engine/**"], "required_checks" => ["rspec"] }]
    )
  end

  describe "#evaluate (critical-tier gate)" do
    it "blocks a critical-tier change pending manual review" do
      contract = build_contract
      service = described_class.new(account: account, risk_contract: contract)

      result = service.evaluate(
        pr_number: 7, head_sha: "abc123", changed_files: changed_files, repository_id: nil
      )

      expect(result[:passed]).to be false
      expect(result[:risk_tier]).to eq("critical")
      expect(result[:reason]).to match(/manual review/i)
      expect(result[:review_state]).to be_present
    end

    it "allows a critical-tier change when the contract opts into critical autoland" do
      contract = build_contract(merge_policy: { "allow_critical_autoland" => true })
      service = described_class.new(account: account, risk_contract: contract)

      result = service.evaluate(
        pr_number: 8, head_sha: "def456", changed_files: changed_files, repository_id: nil
      )

      expect(result[:passed]).to be true
      expect(result[:risk_tier]).to eq("critical")
    end
  end
end
