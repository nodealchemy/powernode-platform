# frozen_string_literal: true

require "rails_helper"

# IMP-3470890a626f — query_learnings chained one .where per keyword (strict
# AND), so any multi-word intent query where the words don't all land in one
# row returned zero results while each single word returned many. The fix
# routes query-bearing calls through CompoundLearningService's existing
# embedding-first retrieval (OR keyword fallback when no embedding), WITHOUT
# record_injection! — an MCP query has no completing execution to credit, so
# counting it as an injection would depress effectiveness exactly the way the
# uncredited dev-loop injections did (IMP-5f8a744b8892).
RSpec.describe Ai::Tools::LearningTool do
  let(:account) { create(:account) }
  let(:user)    { create(:user, account: account) }
  let(:tool)    { described_class.new(account: account, user: user) }

  # Force the keyword-fallback retrieval path deterministically (no embedding
  # infrastructure in specs) — mirrors dev_loop_tool_spec's convention.
  before do
    allow_any_instance_of(Ai::Memory::EmbeddingService).to receive(:generate).and_return(nil)
  end

  let!(:learning) do
    create(:ai_compound_learning, account: account, status: "active",
           title: "Idempotent reconciliation",
           content: "Widget reconciliation must be idempotent across retries",
           importance_score: 0.8)
  end

  describe "query_learnings with a multi-word intent query" do
    it "returns learnings matching ANY of the query words (not strict AND)" do
      # "budget" and "cadence" appear in no learning; under the old chained
      # .where every keyword had to hit the SAME row, so this returned zero.
      result = tool.send(:call, action: "query_learnings",
                               query: "widget reconciliation budget cadence")

      expect(result[:success]).to be true
      expect(result[:learnings].map { |l| l[:id] }).to include(learning.id)
    end

    it "does not record an injection for a recall query" do
      tool.send(:call, action: "query_learnings", query: "widget reconciliation")

      expect(learning.reload.injection_count).to eq(0)
    end

    it "is safe against quote characters in the query" do
      result = tool.send(:call, action: "query_learnings",
                               query: "o'brien's widget reconciliation")

      expect(result[:success]).to be true
      expect(result[:learnings].map { |l| l[:id] }).to include(learning.id)
    end

    it "still honors the category filter on the semantic path" do
      other = create(:ai_compound_learning, account: account, status: "active",
                     category: "failure_mode",
                     content: "Widget reconciliation failure pattern")

      result = tool.send(:call, action: "query_learnings",
                               query: "widget reconciliation", category: "failure_mode")

      ids = result[:learnings].map { |l| l[:id] }
      expect(ids).to include(other.id)
      expect(ids).not_to include(learning.id)
    end
  end

  describe "query_learnings without a query" do
    it "keeps the filtered browse behavior" do
      result = tool.send(:call, action: "query_learnings")

      expect(result[:success]).to be true
      expect(result[:learnings].map { |l| l[:id] }).to include(learning.id)
    end
  end
end
