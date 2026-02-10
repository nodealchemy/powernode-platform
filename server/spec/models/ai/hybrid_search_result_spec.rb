# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::HybridSearchResult, type: :model do
  let(:account) { create(:account) }

  describe "associations" do
    it { should belong_to(:account) }
  end

  describe "validations" do
    it { should validate_presence_of(:query_text) }
    it { should validate_presence_of(:search_mode) }
    it { should validate_inclusion_of(:search_mode).in_array(%w[vector keyword hybrid graph]) }
  end

  describe "scopes" do
    let!(:hybrid_result) { create(:ai_hybrid_search_result, account: account) }
    let!(:vector_result) { create(:ai_hybrid_search_result, :vector_only, account: account) }

    describe ".by_mode" do
      it "filters by search mode" do
        expect(described_class.by_mode("hybrid")).to include(hybrid_result)
        expect(described_class.by_mode("hybrid")).not_to include(vector_result)
      end
    end

    describe ".recent" do
      it "orders by created_at desc" do
        results = described_class.recent
        expect(results.first).to eq(vector_result)
      end
    end
  end

  describe ".avg_latency_for" do
    before do
      create(:ai_hybrid_search_result, account: account, search_mode: "hybrid", total_latency_ms: 100)
      create(:ai_hybrid_search_result, account: account, search_mode: "hybrid", total_latency_ms: 200)
    end

    it "returns average latency for a given mode" do
      expect(described_class.avg_latency_for("hybrid")).to eq(150.0)
    end
  end
end
