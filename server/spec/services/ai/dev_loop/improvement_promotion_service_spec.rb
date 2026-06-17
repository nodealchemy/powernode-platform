# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::DevLoop::ImprovementPromotionService do
  let(:account) { create(:account) }
  let(:recommendation) do
    create(:ai_improvement_recommendation,
           account: account,
           recommendation_type: "dead_code",
           status: "approved",
           confidence_score: 0.8,
           target_type: "Account",
           target_id: account.id,
           evidence: {
             "title" => "Remove dead method",
             "fingerprint" => "dead_code|app/foo.rb|bar",
             "files" => ["app/foo.rb", "app/baz.rb"],
             "description" => "bar is never called"
           })
  end

  describe "#call" do
    it "bootstraps the dev-improve loop manual on first promotion (autonomy is opt-in)" do
      loop_record = described_class.new(recommendation: recommendation).call.ralph_loop

      expect(loop_record.name).to eq("dev-improve")
      expect(loop_record.branch).to eq("dev-loop/dev-improve")
      expect(loop_record.scheduling_mode).to eq("manual")
      expect(loop_record.max_iterations).to eq(500)
    end

    it "creates a task back-linked to the recommendation with kind + blast_radius" do
      result = described_class.new(recommendation: recommendation).call
      task = result.ralph_task

      expect(result.created).to be true
      expect(task.execution_type).to eq("agent")
      expect(task.metadata["recommendation_id"]).to eq(recommendation.id)
      expect(task.metadata["kind"]).to eq("dead_code")
      expect(task.metadata["blast_radius"]).to eq(2) # two files in evidence
      expect(task.priority).to eq(16) # 0.8 * 20
    end

    it "is idempotent — re-promoting reuses the same task" do
      first = described_class.new(recommendation: recommendation).call
      second = described_class.new(recommendation: recommendation).call

      expect(second.created).to be false
      expect(second.ralph_task.id).to eq(first.ralph_task.id)
      expect(first.ralph_loop.ralph_tasks.count).to eq(1)
    end

    it "refuses to promote a recommendation that is not approved" do
      recommendation.update!(status: "pending")
      expect { described_class.new(recommendation: recommendation).call }
        .to raise_error(ArgumentError, /approved/)
    end
  end
end
