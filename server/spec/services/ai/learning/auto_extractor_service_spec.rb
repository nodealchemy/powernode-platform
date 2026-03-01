# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Learning::AutoExtractorService, type: :service do
  let(:account) { create(:account) }
  let(:service) { described_class.new(account: account) }

  before do
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:warn)
    allow(Rails.logger).to receive(:error)
  end

  describe "#extract_from_success" do
    context "with blank output" do
      it "returns empty array" do
        expect(service.extract_from_success(output: nil)).to eq([])
        expect(service.extract_from_success(output: "")).to eq([])
      end
    end

    context "with fast execution" do
      it "extracts performance insight for sub-5s execution" do
        learnings = service.extract_from_success(
          output: "Task completed successfully",
          metadata: { duration_ms: 2000, team_name: "Alpha Team" }
        )

        perf = learnings.find { |l| l[:category] == "performance_insight" }
        expect(perf).to be_present
        expect(perf[:title]).to eq("Fast execution pattern")
        expect(perf[:content]).to include("2000ms")
        expect(perf[:extraction_method]).to eq("auto_success")
      end

      it "does not extract performance insight for slow execution" do
        learnings = service.extract_from_success(
          output: "Done",
          metadata: { duration_ms: 10_000 }
        )

        perf = learnings.find { |l| l[:category] == "performance_insight" }
        expect(perf).to be_nil
      end
    end

    context "with cost-efficient execution" do
      it "extracts cost efficiency pattern" do
        learnings = service.extract_from_success(
          output: "A" * 300,
          metadata: { total_cost_usd: 0.005 }
        )

        cost = learnings.find { |l| l[:category] == "best_practice" }
        expect(cost).to be_present
        expect(cost[:title]).to eq("Cost efficiency pattern")
      end

      it "does not extract for short output" do
        learnings = service.extract_from_success(
          output: "OK",
          metadata: { total_cost_usd: 0.001 }
        )

        cost = learnings.find { |l| l[:title] == "Cost efficiency pattern" }
        expect(cost).to be_nil
      end
    end

    context "with zero-failure tasks" do
      it "extracts zero-failure pattern when all tasks succeed" do
        learnings = service.extract_from_success(
          output: "All done",
          metadata: { tasks_completed: 5, tasks_failed: 0 }
        )

        pattern = learnings.find { |l| l[:category] == "pattern" }
        expect(pattern).to be_present
        expect(pattern[:title]).to eq("Zero-failure execution")
      end

      it "does not extract for too few tasks" do
        learnings = service.extract_from_success(
          output: "Done",
          metadata: { tasks_completed: 1, tasks_failed: 0 }
        )

        pattern = learnings.find { |l| l[:title] == "Zero-failure execution" }
        expect(pattern).to be_nil
      end
    end

    context "with string-keyed metadata" do
      it "handles string keys" do
        learnings = service.extract_from_success(
          output: "Done",
          metadata: { "duration_ms" => 1000, "team_name" => "Beta" }
        )

        perf = learnings.find { |l| l[:category] == "performance_insight" }
        expect(perf).to be_present
      end
    end

    context "with hash output" do
      it "normalizes hash output" do
        learnings = service.extract_from_success(
          output: { "text" => "A" * 300 },
          metadata: { total_cost_usd: 0.005 }
        )

        expect(learnings).not_to be_empty
      end
    end
  end

  describe "#extract_from_failure" do
    context "with blank error" do
      it "returns empty array" do
        expect(service.extract_from_failure(error: nil)).to eq([])
        expect(service.extract_from_failure(error: "")).to eq([])
      end
    end

    it "extracts failure mode learning" do
      learnings = service.extract_from_failure(error: "Connection timeout after 30s")

      failure = learnings.find { |l| l[:category] == "failure_mode" }
      expect(failure).to be_present
      expect(failure[:title]).to eq("Timeout failure")
      expect(failure[:confidence]).to eq(0.8)
      expect(failure[:extraction_method]).to eq("auto_failure")
    end

    it "classifies rate limit errors" do
      learnings = service.extract_from_failure(error: "429 Too Many Requests")
      failure = learnings.first
      expect(failure[:title]).to eq("Rate limit hit")
    end

    it "classifies auth errors" do
      learnings = service.extract_from_failure(error: "401 Unauthorized")
      failure = learnings.first
      expect(failure[:title]).to eq("Auth failure")
    end

    it "classifies token limit errors" do
      learnings = service.extract_from_failure(error: "Token limit exceeded")
      failure = learnings.first
      expect(failure[:title]).to eq("Token limit exceeded")
    end

    it "classifies network errors" do
      learnings = service.extract_from_failure(error: "DNS resolution failed")
      failure = learnings.first
      expect(failure[:title]).to eq("Connection failure")
    end

    it "classifies memory errors with high importance" do
      learnings = service.extract_from_failure(error: "Out of memory")
      failure = learnings.first
      expect(failure[:title]).to eq("Memory exhaustion")
    end

    it "defaults to general failure for unknown errors" do
      learnings = service.extract_from_failure(error: "Something unexpected happened")
      failure = learnings.first
      expect(failure[:title]).to eq("General failure")
    end

    context "with high failure rate" do
      it "extracts anti-pattern for >= 50% failure rate" do
        learnings = service.extract_from_failure(
          error: "Task failed",
          metadata: { tasks_failed: 5, tasks_total: 8 }
        )

        anti = learnings.find { |l| l[:category] == "anti_pattern" }
        expect(anti).to be_present
        expect(anti[:title]).to eq("High failure rate detected")
        expect(anti[:importance]).to eq(0.85)
      end

      it "does not extract anti-pattern for low failure rate" do
        learnings = service.extract_from_failure(
          error: "Task failed",
          metadata: { tasks_failed: 1, tasks_total: 10 }
        )

        anti = learnings.find { |l| l[:title] == "High failure rate detected" }
        expect(anti).to be_nil
      end
    end

    it "truncates long error messages" do
      long_error = "x" * 1000
      learnings = service.extract_from_failure(error: long_error)
      failure = learnings.first
      expect(failure[:content].length).to be < 600
    end
  end

  describe "#extract_from_review" do
    context "with non-TaskReview input" do
      it "returns empty array for nil" do
        expect(service.extract_from_review(nil)).to eq([])
      end

      it "returns empty array for non-TaskReview objects" do
        expect(service.extract_from_review("not a review")).to eq([])
      end
    end

    context "with a rejected review" do
      let(:review) do
        instance_double(Ai::TaskReview,
                        is_a?: true,
                        status: "rejected",
                        rejection_reason: "Code doesn't handle edge cases",
                        revision_count: 0)
      end

      before do
        allow(review).to receive(:is_a?).with(Ai::TaskReview).and_return(true)
        allow(review).to receive(:respond_to?).with(:code_review_comments).and_return(false)
      end

      it "extracts rejection anti-pattern" do
        learnings = service.extract_from_review(review)

        anti = learnings.find { |l| l[:category] == "anti_pattern" }
        expect(anti).to be_present
        expect(anti[:title]).to eq("Review rejection pattern")
        expect(anti[:extraction_method]).to eq("review")
      end
    end

    context "with revision requested" do
      let(:review) do
        instance_double(Ai::TaskReview,
                        status: "revision_requested",
                        rejection_reason: "Missing tests",
                        revision_count: 1)
      end

      before do
        allow(review).to receive(:is_a?).with(Ai::TaskReview).and_return(true)
        allow(review).to receive(:respond_to?).with(:code_review_comments).and_return(false)
      end

      it "extracts revision pattern" do
        learnings = service.extract_from_review(review)

        revision = learnings.find { |l| l[:category] == "review_finding" }
        expect(revision).to be_present
        expect(revision[:title]).to eq("Revision pattern")
      end
    end

    context "with multiple revisions" do
      let(:review) do
        instance_double(Ai::TaskReview,
                        status: "approved",
                        rejection_reason: nil,
                        revision_count: 3)
      end

      before do
        allow(review).to receive(:is_a?).with(Ai::TaskReview).and_return(true)
        allow(review).to receive(:respond_to?).with(:code_review_comments).and_return(false)
      end

      it "extracts multi-revision anti-pattern" do
        learnings = service.extract_from_review(review)

        anti = learnings.find { |l| l[:title] == "Multi-revision anti-pattern" }
        expect(anti).to be_present
        expect(anti[:content]).to include("3 revisions")
      end
    end
  end

  describe "#extract_from_evaluations" do
    let(:agent) { create(:ai_agent, account: account) }
    let(:execution_id) { SecureRandom.uuid }

    context "when no evaluation results exist" do
      it "returns empty array" do
        learnings = service.extract_from_evaluations(execution_id: execution_id)
        expect(learnings).to eq([])
      end
    end

    context "with high-scoring evaluation" do
      let!(:result) do
        create(:ai_evaluation_result,
               account: account, agent: agent, execution_id: execution_id,
               scores: { "correctness" => 4.5, "completeness" => 4.8, "helpfulness" => 4.7, "safety" => 5.0 })
      end

      it "extracts best practice learning" do
        learnings = service.extract_from_evaluations(execution_id: execution_id)

        best = learnings.find { |l| l[:category] == "best_practice" }
        expect(best).to be_present
        expect(best[:title]).to eq("High quality execution")
        expect(best[:extraction_method]).to eq("evaluation")
      end
    end

    context "with low-scoring evaluation" do
      let!(:result) do
        create(:ai_evaluation_result,
               account: account, agent: agent, execution_id: execution_id,
               scores: { "correctness" => 1.5, "completeness" => 1.2, "helpfulness" => 1.8, "safety" => 2.0 })
      end

      it "extracts anti-pattern learning" do
        learnings = service.extract_from_evaluations(execution_id: execution_id)

        anti = learnings.find { |l| l[:category] == "anti_pattern" }
        expect(anti).to be_present
        expect(anti[:title]).to eq("Low quality execution")
      end
    end

    context "with mid-range evaluation" do
      let!(:result) do
        create(:ai_evaluation_result,
               account: account, agent: agent, execution_id: execution_id,
               scores: { "correctness" => 3.0, "completeness" => 3.2, "helpfulness" => 3.0, "safety" => 3.5 })
      end

      it "does not extract learnings for mid-range scores" do
        learnings = service.extract_from_evaluations(execution_id: execution_id)
        expect(learnings).to be_empty
      end
    end
  end
end
