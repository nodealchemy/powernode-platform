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

  # IMP-7f415874c14a: #extract now derives its entries from ai_ralph_iterations
  # (RalphLoop#learning_entries), not the retired `learnings` jsonb column. These
  # fixtures seed the surviving sink; seeding only the array pinned a dead reader.
  def seed_learnings!(loop_record, *texts)
    texts.each_with_index do |text, index|
      create(:ai_ralph_iteration, ralph_loop: loop_record,
             iteration_number: index + 1, learning_extracted: text)
    end
    loop_record
  end

  describe "#extract" do
    it "promotes each loop learning into a durable, titled, repo-scoped CompoundLearning" do
      loop_record = seed_learnings!(
        create(:ai_ralph_loop, account: account, repository_url: repo.clone_url),
        "Prefer a scope over a class method here",
        "An N+1 lurks in the serializer"
      )

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
      loop_record = seed_learnings!(create(:ai_ralph_loop, account: account),
                                    "a uniquely phrased insight A")
      extractor = described_class.new(account: account)
      extractor.extract(loop_record)

      expect { extractor.extract(loop_record) }.not_to change(Ai::CompoundLearning, :count)
    end

    it "skips blank rows" do
      loop_record = create(:ai_ralph_loop, account: account)
      create(:ai_ralph_iteration, ralph_loop: loop_record, iteration_number: 1, learning_extracted: "")
      create(:ai_ralph_iteration, ralph_loop: loop_record, iteration_number: 2,
             learning_extracted: "a row-backed insight")

      expect { described_class.new(account: account).extract(loop_record) }
        .to change(Ai::CompoundLearning, :count).by(1)
    end

    # #reset! supplies `entries:` from a pre-delete capture, so the entry-shape
    # tolerance is still reachable and still has to hold.
    it "skips blank entries and tolerates plain-string entries supplied via `entries:`" do
      loop_record = create(:ai_ralph_loop, account: account)

      expect {
        described_class.new(account: account)
                       .extract(loop_record, entries: [ { "text" => "" }, "a plain string insight" ])
      }.to change(Ai::CompoundLearning, :count).by(1)
    end

    it "leaves git_repository_id nil when the loop has no resolvable repository" do
      loop_record = seed_learnings!(
        create(:ai_ralph_loop, account: account, repository_url: nil), "an insight with no repo"
      )
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
      loop_record = seed_learnings!(create(:ai_ralph_loop, account: account),
                                    "some genuinely useful loop insight")
      extractor.extract(loop_record, entries: loop_record.learning_entries + [ "a bare-string insight" ])

      produced = Ai::CompoundLearning.where(extraction_method: "ralph_loop")
      expect(produced).to be_present
      expect(produced.map(&:title)).to all(be_present)   # never null/blank
    end
  end

  describe "RalphLoop#complete! wiring" do
    it "harvests learnings into CompoundLearning on completion" do
      loop_record = seed_learnings!(create(:ai_ralph_loop, :running, account: account),
                                    "a completion-harvest insight")

      expect { loop_record.complete! }.to change(Ai::CompoundLearning, :count).by(1)
    end

    it "is a no-op for a loop with no learnings" do
      loop_record = create(:ai_ralph_loop, :running, account: account)
      expect { loop_record.complete! }.not_to change(Ai::CompoundLearning, :count)
    end
  end

  # IMP-077c2471b85a. #extract_entry! is #extract's non-rescuing, single-jsonb-
  # entry sibling for ai:drain_dormant_ralph_learnings, which cannot afford
  # #extract's method-level rescue collapsing "raised" and "deduped" into the
  # same falsy-ish outcome for a source it is about to erase.
  describe "#extract_entry!" do
    let(:extractor) { described_class.new(account: account) }
    let(:loop_record) { create(:ai_ralph_loop, account: account) }

    it "returns true and creates a durable record for a new entry" do
      created = nil
      expect { created = extractor.extract_entry!(loop_record, { "text" => "a stranded legacy entry" }) }
        .to change(Ai::CompoundLearning, :count).by(1)

      expect(created).to be(true)
    end

    it "returns false without raising when the content is a near-duplicate" do
      extractor.extract_entry!(loop_record, { "text" => "a repeated stranded entry" })

      result = nil
      expect { result = extractor.extract_entry!(loop_record, { "text" => "a repeated stranded entry" }) }
        .not_to change(Ai::CompoundLearning, :count)
      expect(result).to be(false)
    end

    it "propagates a storage failure instead of swallowing it" do
      allow_any_instance_of(Ai::Learning::CompoundLearningService)
        .to receive(:store_learning).and_raise(StandardError, "embedding provider unreachable")

      expect { extractor.extract_entry!(loop_record, { "text" => "would be lost if swallowed" }) }
        .to raise_error(StandardError, "embedding provider unreachable")
    end
  end
end
