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

  # IMP-095a5fe91b4a. verify_learning_batch's per-id rescue is a `rescue
  # StandardError => e` attached to the BLOCK passed to Array#map, not to any
  # method definition — invisible to a scanner that only walks rescue nodes
  # under method DEFINITIONS. It fed `e.message` straight into `reason:`, a
  # batch-payload key the shape-keyed scanner (looking only for `error:` /
  # `error_result(` / `success: false`) also never matched. Both blind spots
  # let a raw driver message (a PG constraint violation, for instance) reach
  # the batch payload that is forwarded to the model provider.
  describe "verify_learning_batch does not leak a raw exception message per-item" do
    it "sanitizes a raw driver message from an individual verify! failure without dropping the batch" do
      own = create(:ai_compound_learning, account: account_a, status: "active")
      raw = 'PG::UniqueViolation: ERROR:  duplicate key value violates unique constraint ' \
            '"index_ai_compound_learnings_on_verification_token"'
      allow_any_instance_of(Ai::CompoundLearning).to receive(:verify!).and_raise(StandardError, raw)
      allow(Rails.logger).to receive(:error)

      result = tool.execute(params: { action: "verify_learning_batch", learning_ids: [own.id] })

      expect(result[:success]).to be true
      entry = result[:results].first
      expect(entry[:id]).to eq(own.id)
      expect(entry[:ok]).to be false
      expect(entry[:reason]).not_to include("PG::UniqueViolation")
      expect(entry[:reason]).not_to include("constraint")
      expect(entry[:reason]).not_to include("index_ai_compound_learnings")
    end

    it "still logs the raw exception server-side" do
      own = create(:ai_compound_learning, account: account_a, status: "active")
      raw = 'PG::UniqueViolation: duplicate key value violates unique constraint "some_index"'
      allow_any_instance_of(Ai::CompoundLearning).to receive(:verify!).and_raise(StandardError, raw)
      expect(Rails.logger).to receive(:error).with(a_string_including("PG::UniqueViolation", "some_index"))

      tool.execute(params: { action: "verify_learning_batch", learning_ids: [own.id] })
    end
  end
end
