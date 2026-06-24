# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Tools::KnowledgeQualityTool do
  let(:account_a) { create(:account) }
  let(:account_b) { create(:account) }
  let(:user_a) { create(:user, account: account_a) }
  let(:tool) { described_class.new(account: account_a, user: user_a) }

  describe "cross-account isolation (IDOR)" do
    it "unsupersede_learning cannot revive another account's learning" do
      other = create(:ai_compound_learning, account: account_b, status: "deprecated")

      result = tool.execute(params: { action: "unsupersede_learning", learning_id: other.id })

      expect(result[:success]).to be false
      expect(result[:error]).to match(/not found/i)
      expect(other.reload.status).to eq("deprecated")
    end

    it "verify_learning_batch cannot verify another account's learning" do
      other = create(:ai_compound_learning, account: account_b, status: "active")

      result = tool.execute(params: { action: "verify_learning_batch", learning_ids: [other.id] })

      expect(result[:success]).to be true
      expect(result[:verified]).to eq(0)
      entry = result[:results].first
      expect(entry[:ok]).to be false
      expect(entry[:reason]).to match(/not_found/i)
      expect(other.reload.status).to eq("active")
    end
  end

  describe "legitimate same-account access" do
    it "unsupersede_learning revives the account's own deprecated learning" do
      own = create(:ai_compound_learning, account: account_a, status: "deprecated")

      result = tool.execute(params: { action: "unsupersede_learning", learning_id: own.id })

      expect(result[:success]).to be true
      expect(own.reload.status).to eq("active")
    end

    it "verify_learning_batch verifies the account's own active learning" do
      own = create(:ai_compound_learning, account: account_a, status: "active")

      result = tool.execute(params: { action: "verify_learning_batch", learning_ids: [own.id] })

      expect(result[:success]).to be true
      expect(result[:verified]).to eq(1)
      expect(own.reload.status).to eq("verified")
    end
  end
end
