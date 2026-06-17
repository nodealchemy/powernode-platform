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
    it "promotes each loop learning into a durable, low-importance, repo-scoped CompoundLearning" do
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
      expect(cl.importance_score).to eq(0.3)
      expect(cl.category).to eq("discovery")
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
