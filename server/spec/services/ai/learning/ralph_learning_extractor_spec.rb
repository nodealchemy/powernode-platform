# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Learning::RalphLearningExtractor, type: :service do
  let(:account) { create(:account) }
  let(:repo) { create(:git_repository, account: account) }

  before do
    # Force store_learning's text-dedup path so creation is deterministic without
    # a live embedding backend.
    allow_any_instance_of(Ai::Memory::EmbeddingService).to receive(:generate).and_return(nil)
  end

  describe "#extract" do
    it "promotes each loop learning into a durable, titled, repo-scoped CompoundLearning" do
      loop_record = create(:ai_ralph_loop, account: account, repository_url: repo.clone_url,
                           learnings: [
                             { "text" => "Prefer a scope over a class method here", "iteration" => 1 },
                             { "text" => "An N+1 lurks in the serializer", "iteration" => 2 }
                           ])

      count = nil
      expect { count = described_class.new(account: account).extract(loop_record) }
        .to change(Ai::CompoundLearning, :count).by(2)

      expect(count).to eq(2)
      cl = Ai::CompoundLearning.where(extraction_method: "ralph_loop").last
      # Calibrated (not blanket 0.3): discovery base, non-campaign loop.
      expect(cl.importance_score).to eq(0.35)
      expect(cl.category).to eq("discovery")
      expect(cl.title).to eq("An N+1 lurks in the serializer") # derived, never null
      expect(cl.git_repository_id).to eq(repo.id) # resolved from repository_url
      expect(cl.tags).to include("ralph_loop")
    end

    it "is idempotent — re-extracting the same learnings does not duplicate" do
      loop_record = create(:ai_ralph_loop, account: account,
                           learnings: [{ "text" => "a uniquely phrased insight A" }])
      extractor = described_class.new(account: account)
      extractor.extract(loop_record)

      expect { extractor.extract(loop_record) }.not_to change(Ai::CompoundLearning, :count)
    end

    it "skips blank learnings and tolerates plain-string entries" do
      loop_record = create(:ai_ralph_loop, account: account,
                           learnings: [{ "text" => "" }, "a plain string insight"])

      expect { described_class.new(account: account).extract(loop_record) }
        .to change(Ai::CompoundLearning, :count).by(1)
    end

    it "leaves git_repository_id nil when the loop has no resolvable repository" do
      loop_record = create(:ai_ralph_loop, account: account, repository_url: nil,
                           learnings: [{ "text" => "an insight with no repo" }])
      described_class.new(account: account).extract(loop_record)

      expect(Ai::CompoundLearning.where(extraction_method: "ralph_loop").last.git_repository_id).to be_nil
    end
  end

  describe "creation quality (inc7 feed-forward seam)" do
    subject(:extractor) { described_class.new(account: account) }

    def last_ralph_learning
      Ai::CompoundLearning.where(extraction_method: "ralph_loop").order(:created_at).last
    end

    it "derives a bounded title from the first sentence and strips a leading marker" do
      loop_record = create(:ai_ralph_loop, account: account)
      extractor.extract_learning(loop_record,
        "Pattern: prefer a scope over a class method. It reads better and dedups the query.")

      cl = last_ralph_learning
      expect(cl.title).to eq("prefer a scope over a class method")
      expect(cl.category).to eq("pattern")           # marker-driven
      expect(cl.content).to start_with("Pattern:")   # content is untouched
    end

    it "caps an over-long, delimiter-free title at the bound with an ellipsis" do
      loop_record = create(:ai_ralph_loop, account: account)
      long = "x" * 200
      extractor.extract_learning(loop_record, long)

      title = last_ralph_learning.title
      expect(title.length).to be <= described_class::TITLE_MAX
      expect(title).to end_with("…")
    end

    it "derives class/topic tags from loop workload, task-key domain, and changed-file subsystem" do
      loop_record = create(:ai_ralph_loop, account: account,
                           name: "dev-improve", configuration: { "workload" => "improvement-discovery" })
      extractor.extract_learning(loop_record, "The webhook receiver must not 500",
        context: { task_key: "IMP-abc123", files: ["server/app/services/ai/foo.rb", "frontend/src/x.tsx"] })

      tags = last_ralph_learning.tags
      expect(tags).to include("ralph_loop", "improvement-discovery", "task:imp",
                              "subsystem:server", "subsystem:frontend", "subsystem:ai")
    end

    it "honors caller-supplied explicit tags and boosts importance for campaign-directed loops" do
      campaign = create(:ai_campaign, account: account)
      loop_record = create(:ai_ralph_loop, account: account, campaign: campaign)
      extractor.extract_learning(loop_record, "Escalation rationale must be built at classify time",
        context: { tags: ["escalation", "governance"] })

      cl = last_ralph_learning
      expect(cl.tags).to include("campaign", "escalation", "governance")
      # discovery base 0.35 + campaign boost 0.15
      expect(cl.importance_score).to eq(0.5)
    end

    it "lets an explicit category/importance override the derived values" do
      loop_record = create(:ai_ralph_loop, account: account)
      extractor.extract_learning(loop_record, "A durable best-practice rule",
        context: { category: "best_practice", importance: 0.62 })

      cl = last_ralph_learning
      expect(cl.category).to eq("best_practice")
      expect(cl.importance_score).to eq(0.62)
    end

    it "REGRESSION: can no longer produce the write-only null-title shape" do
      loop_record = create(:ai_ralph_loop, account: account,
                           learnings: [{ "text" => "some genuinely useful loop insight" },
                                       "a bare-string insight"])
      extractor.extract(loop_record)

      produced = Ai::CompoundLearning.where(extraction_method: "ralph_loop")
      expect(produced).to be_present
      expect(produced.map(&:title)).to all(be_present)   # never null/blank
    end
  end

  describe "RalphLoop#complete! wiring" do
    it "harvests learnings into CompoundLearning on completion" do
      loop_record = create(:ai_ralph_loop, :running, account: account,
                           learnings: [{ "text" => "a completion-harvest insight" }])

      expect { loop_record.complete! }.to change(Ai::CompoundLearning, :count).by(1)
    end

    it "is a no-op for a loop with no learnings" do
      loop_record = create(:ai_ralph_loop, :running, account: account, learnings: [])
      expect { loop_record.complete! }.not_to change(Ai::CompoundLearning, :count)
    end
  end
end
