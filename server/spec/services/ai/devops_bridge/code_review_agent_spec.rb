# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::DevopsBridge::CodeReviewAgent, type: :service do
  let(:account) { create(:account) }
  let(:service) { described_class.new(account: account) }

  before do
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:warn)
    allow(Rails.logger).to receive(:error)
  end

  describe "REVIEW_DIMENSIONS" do
    it "includes security, performance, correctness, style" do
      expect(described_class::REVIEW_DIMENSIONS).to eq(%w[security performance correctness style])
    end
  end

  describe "#review_pull_request" do
    let(:repository) { double("Repository", name: "my-repo") }
    let(:pr_context) do
      {
        repository_name: "my-repo",
        title: "Add feature",
        description: "New feature implementation",
        diff: "diff --git a/app.rb b/app.rb\n+new code"
      }
    end

    let(:mock_context_builder) { instance_double(Ai::DevopsBridge::PrContextBuilder) }

    before do
      allow(Ai::DevopsBridge::PrContextBuilder).to receive(:new).and_return(mock_context_builder)
    end

    context "when PR context cannot be fetched" do
      before do
        allow(mock_context_builder).to receive(:build).and_return(nil)
      end

      it "returns an error" do
        result = service.review_pull_request(repository: repository, pr_number: 1)
        expect(result[:error]).to eq("Could not fetch PR context")
      end
    end

    context "when PR context is available" do
      let(:agent) { create(:ai_agent, account: account, status: "active") }
      let(:orchestration_service) { double("AgentOrchestrationService") }

      before do
        allow(mock_context_builder).to receive(:build).and_return(pr_context)
        allow(Ai::AgentOrchestrationService).to receive(:new).and_return(orchestration_service)
      end

      context "when agents execute successfully" do
        before do
          allow(service).to receive(:find_review_agent).and_return(agent)
          allow(orchestration_service).to receive(:execute_agent).and_return(
            { output: "No issues found" }
          )
        end

        it "returns review results for all dimensions" do
          result = service.review_pull_request(repository: repository, pr_number: 42)

          expect(result[:pr_number]).to eq(42)
          expect(result[:repository]).to eq("my-repo")
          expect(result[:reviews]).to be_an(Array)
          expect(result[:reviews].length).to eq(4)
          expect(result[:summary]).to be_a(String)
          expect(result[:reviewed_at]).to be_present
        end

        it "includes dimension details in each review" do
          result = service.review_pull_request(repository: repository, pr_number: 1)

          review = result[:reviews].first
          expect(review).to include(:dimension, :agent_id, :agent_name, :findings, :severity)
        end
      end

      context "when no review agent is found" do
        before do
          allow(service).to receive(:find_review_agent).and_return(nil)
        end

        it "returns compact results (nils removed)" do
          result = service.review_pull_request(repository: repository, pr_number: 1)

          expect(result[:reviews]).to be_empty
        end
      end

      context "when agent execution fails" do
        before do
          allow(service).to receive(:find_review_agent).and_return(agent)
          allow(orchestration_service).to receive(:execute_agent).and_raise(StandardError, "LLM timeout")
        end

        it "handles errors gracefully and returns nil for that dimension" do
          result = service.review_pull_request(repository: repository, pr_number: 1)

          expect(result[:reviews]).to be_empty
        end
      end
    end
  end

  describe "classify_severity (private)" do
    it "classifies critical output" do
      expect(service.send(:classify_severity, "[CRITICAL] SQL injection found")).to eq("critical")
    end

    it "classifies vulnerability mentions as critical" do
      expect(service.send(:classify_severity, "XSS vulnerability detected")).to eq("critical")
    end

    it "classifies warning output" do
      expect(service.send(:classify_severity, "[WARNING] Unused import")).to eq("warning")
    end

    it "classifies high severity as warning" do
      expect(service.send(:classify_severity, "[HIGH] Performance issue")).to eq("warning")
    end

    it "defaults to info for normal output" do
      expect(service.send(:classify_severity, "Code looks clean")).to eq("info")
    end

    it "returns info for nil output" do
      expect(service.send(:classify_severity, nil)).to eq("info")
    end
  end

  describe "generate_summary (private)" do
    it "summarizes review results" do
      results = [
        { severity: "critical" },
        { severity: "warning" },
        { severity: "info" },
        { severity: "info" }
      ]

      summary = service.send(:generate_summary, results)
      expect(summary).to eq("Reviewed 4 dimensions. 1 critical, 1 warnings.")
    end

    it "handles empty results" do
      summary = service.send(:generate_summary, [])
      expect(summary).to eq("Reviewed 0 dimensions. 0 critical, 0 warnings.")
    end
  end
end
