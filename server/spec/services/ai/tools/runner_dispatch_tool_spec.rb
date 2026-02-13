# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Tools::RunnerDispatchTool do
  let(:account) { create(:account) }
  let(:tool) { described_class.new(account: account) }

  describe ".definition" do
    it "returns a valid tool definition" do
      defn = described_class.definition
      expect(defn[:name]).to eq("dispatch_to_runner")
      expect(defn[:description]).to be_present
      expect(defn[:parameters]).to include(:session_id, :worktree_id, :task_input, :runner_labels)
    end

    it "marks session_id and worktree_id as required" do
      params = described_class.definition[:parameters]
      expect(params[:session_id][:required]).to be true
      expect(params[:worktree_id][:required]).to be true
    end
  end

  describe ".permitted?" do
    it "requires ai.workflows.execute permission" do
      expect(described_class::REQUIRED_PERMISSION).to eq("ai.workflows.execute")
    end
  end

  describe "#execute" do
    let(:session) { instance_double("Ai::WorktreeSession", worktrees: worktrees_scope) }
    let(:worktree) { instance_double("Ai::Worktree") }
    let(:worktrees_scope) { double("worktrees_scope") }
    let(:sessions_scope) { double("sessions_scope") }
    let(:dispatch_service) { instance_double(Ai::RunnerDispatchService) }
    let(:runner) { double("runner") }

    before do
      allow(account).to receive(:ai_worktree_sessions).and_return(sessions_scope)
      allow(sessions_scope).to receive(:find).with("session-1").and_return(session)
      allow(worktrees_scope).to receive(:find).with("worktree-1").and_return(worktree)
      allow(Ai::RunnerDispatchService).to receive(:new).with(account: account, session: session).and_return(dispatch_service)
    end

    context "when a runner is available" do
      it "dispatches to the runner" do
        allow(dispatch_service).to receive(:select_runner).with(required_labels: []).and_return(runner)
        allow(dispatch_service).to receive(:dispatch).with(worktree: worktree, task_input: {}, runner: runner).and_return({ success: true })

        result = tool.execute(params: { session_id: "session-1", worktree_id: "worktree-1" })
        expect(result[:success]).to be true
      end

      it "passes runner_labels to select_runner" do
        allow(dispatch_service).to receive(:select_runner).with(required_labels: ["gpu"]).and_return(runner)
        allow(dispatch_service).to receive(:dispatch).and_return({ success: true })

        tool.execute(params: { session_id: "session-1", worktree_id: "worktree-1", runner_labels: ["gpu"] })
        expect(dispatch_service).to have_received(:select_runner).with(required_labels: ["gpu"])
      end

      it "passes task_input to dispatch" do
        allow(dispatch_service).to receive(:select_runner).and_return(runner)
        allow(dispatch_service).to receive(:dispatch).with(worktree: worktree, task_input: { "prompt" => "test" }, runner: runner).and_return({ success: true })

        tool.execute(params: { session_id: "session-1", worktree_id: "worktree-1", task_input: { "prompt" => "test" } })
        expect(dispatch_service).to have_received(:dispatch).with(worktree: worktree, task_input: { "prompt" => "test" }, runner: runner)
      end
    end

    context "when no runner is available" do
      it "returns error" do
        allow(dispatch_service).to receive(:select_runner).and_return(nil)

        result = tool.execute(params: { session_id: "session-1", worktree_id: "worktree-1" })
        expect(result[:success]).to be false
        expect(result[:error]).to match(/No available runner/)
      end
    end

    context "parameter validation" do
      it "raises ArgumentError when session_id is missing" do
        expect { tool.execute(params: { worktree_id: "wt-1" }) }.to raise_error(ArgumentError, /Missing required parameters/)
      end

      it "raises ArgumentError when worktree_id is missing" do
        expect { tool.execute(params: { session_id: "s-1" }) }.to raise_error(ArgumentError, /Missing required parameters/)
      end
    end
  end
end
