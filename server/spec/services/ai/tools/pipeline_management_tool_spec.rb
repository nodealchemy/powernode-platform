# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Tools::PipelineManagementTool do
  let(:account) { create(:account) }
  let(:tool) { described_class.new(account: account) }

  describe ".definition" do
    it "returns a valid tool definition" do
      defn = described_class.definition
      expect(defn[:name]).to eq("pipeline_management")
      expect(defn[:description]).to be_present
      expect(defn[:parameters]).to include(:action, :pipeline_id, :repository_id, :branch)
    end

    it "marks action as required" do
      expect(described_class.definition[:parameters][:action][:required]).to be true
    end
  end

  describe ".permitted?" do
    it "requires git.pipelines.manage permission" do
      expect(described_class::REQUIRED_PERMISSION).to eq("git.pipelines.manage")
    end
  end

  describe "#execute" do
    context "with trigger_pipeline action" do
      let(:pipeline) { create(:devops_pipeline, account: account) }

      before { allow(WorkerJobService).to receive(:enqueue_job).and_return(true) }

      it "creates a pending run and queues the execution job (no fabricated success)" do
        expect(WorkerJobService).to receive(:enqueue_job)
          .with("Devops::PipelineExecutionJob", hash_including(queue: "devops_high"))
        result = nil
        expect {
          result = tool.execute(params: { action: "trigger_pipeline", pipeline_id: pipeline.id })
        }.to change { pipeline.runs.count }.by(1)
        expect(result[:success]).to be true
        expect(result[:run_id]).to eq(pipeline.runs.last.id)
        expect(result[:queued]).to be true
      end

      it "returns error for a non-existent pipeline" do
        result = tool.execute(params: { action: "trigger_pipeline", pipeline_id: SecureRandom.uuid })
        expect(result[:success]).to be false
        expect(result[:error]).to match(/not found/i)
      end

      it "requires pipeline_id" do
        result = tool.execute(params: { action: "trigger_pipeline" })
        expect(result[:success]).to be false
        expect(result[:error]).to match(/pipeline_id/i)
      end
    end

    context "with list_pipelines action" do
      let(:repo) { create(:git_repository, account: account) }
      let(:other_repo) { create(:git_repository, account: account) }
      let!(:mine) { create(:git_pipeline, account: account, repository: repo, name: "CI main") }
      let!(:sibling) { create(:git_pipeline, account: account, repository: other_repo, name: "CI other") }
      let!(:foreign) { create(:git_pipeline, name: "CI foreign") }

      # It used to return only `count` (of a .limit(50) relation) and never the
      # pipelines, and its repository filter fell through to the account scope.
      it "returns the account's pipelines, paginated" do
        result = tool.execute(params: { action: "list_pipelines" })

        expect(result[:success]).to be true
        expect(result[:data][:pipelines].map { |p| p[:id] }).to contain_exactly(mine.id, sibling.id)
        expect(result[:data][:pipelines].first).to include(:name, :status, :conclusion, :repository_id, :ref)
        expect(result[:data]).to include(count: 2, has_more: false)
      end

      it "narrows to one repository" do
        result = tool.execute(params: { action: "list_pipelines", repository_id: repo.id })

        expect(result[:data][:pipelines].map { |p| p[:id] }).to eq([ mine.id ])
      end

      it "pages with the cursor" do
        first = tool.execute(params: { action: "list_pipelines", limit: 1 })
        second = tool.execute(params: { action: "list_pipelines", limit: 1, cursor: first[:data][:next_cursor] })

        expect(first[:data][:has_more]).to be true
        expect((first[:data][:pipelines] + second[:data][:pipelines]).map { |p| p[:id] }).to contain_exactly(mine.id, sibling.id)
      end

      it "refuses another account's repository" do
        result = tool.execute(params: { action: "list_pipelines", repository_id: foreign.repository.id })

        expect(result[:success]).to be false
      end
    end

    context "with get_pipeline_status action" do
      it "returns error for non-existent pipeline" do
        result = tool.execute(params: { action: "get_pipeline_status", pipeline_id: SecureRandom.uuid })
        expect(result[:success]).to be false
        expect(result[:error]).to match(/not found/i)
      end
    end

    context "with unknown action" do
      it "returns error" do
        result = tool.execute(params: { action: "self_destruct" })
        expect(result[:success]).to be false
        expect(result[:error]).to match(/Unknown action/)
      end
    end

    context "parameter validation" do
      it "raises ArgumentError when action is missing" do
        expect { tool.execute(params: {}) }.to raise_error(ArgumentError, /Missing required parameters: action/)
      end
    end
  end
end
