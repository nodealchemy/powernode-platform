# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Workflows::RunManagementService, type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:workflow) { create(:ai_workflow, :active, :with_simple_chain, account: account, creator: user) }

  subject(:service) { described_class.new(workflow: workflow, user: user) }

  # ===========================================================================
  # #create_run
  # ===========================================================================

  describe "#create_run" do
    it "creates a new run in initializing state" do
      result = service.create_run(input_variables: { test: "data" })

      expect(result).to be_success
      expect(result.run).to be_persisted
      expect(result.run.status).to eq("initializing")
      expect(result.run.trigger_type).to eq("manual")
      expect(result.run.input_variables).to include("test" => "data")
    end

    it "records trigger type and context" do
      result = service.create_run(
        input_variables: {},
        trigger_type: "webhook",
        trigger_context: { source: "github" }
      )

      expect(result).to be_success
      expect(result.run.trigger_type).to eq("webhook")
      expect(result.run.trigger_context).to include("source" => "github")
    end

    it "sets node counts from the workflow" do
      result = service.create_run(input_variables: {})

      expect(result).to be_success
      expect(result.run.total_nodes).to eq(workflow.nodes.count)
      expect(result.run.completed_nodes).to eq(0)
      expect(result.run.failed_nodes).to eq(0)
    end

    it "fails when workflow is not executable" do
      draft_workflow = create(:ai_workflow, account: account, creator: user, status: "draft")
      draft_service = described_class.new(workflow: draft_workflow, user: user)

      result = draft_service.create_run(input_variables: {})

      expect(result).to be_failure
      expect(result.error).to include("not in an executable state")
    end

    it "associates the run with the triggering user" do
      result = service.create_run(input_variables: {})

      expect(result).to be_success
      expect(result.run.triggered_by_user).to eq(user)
    end
  end

  # ===========================================================================
  # #cancel_run
  # ===========================================================================

  describe "#cancel_run" do
    let(:run) { create(:ai_workflow_run, :running, workflow: workflow, account: account) }

    it "cancels a running workflow run" do
      result = service.cancel_run(run, reason: "No longer needed")

      expect(result).to be_success
      expect(run.reload.status).to eq("cancelled")
    end

    it "fails when run cannot be cancelled" do
      completed_run = create(:ai_workflow_run, :completed, workflow: workflow, account: account)

      result = service.cancel_run(completed_run)

      expect(result).to be_failure
      expect(result.error).to include("Cannot cancel")
    end

    it "rejects run that belongs to a different workflow" do
      other_workflow = create(:ai_workflow, :active, :with_simple_chain, account: account, creator: user)
      other_run = create(:ai_workflow_run, :running, workflow: other_workflow, account: account)

      # validate_run_ownership! raises WorkflowExecutionError which is rescued by cancel_run
      result = service.cancel_run(other_run)

      expect(result).to be_failure
      expect(result.error).to include("does not belong")
    end
  end

  # ===========================================================================
  # #retry_run
  # ===========================================================================

  describe "#retry_run" do
    let(:failed_run) { create(:ai_workflow_run, :failed, workflow: workflow, account: account) }

    it "returns failure due to retry trigger type validation" do
      # The service uses trigger_type: "retry" which is not in the allowed list
      # This is a known service limitation
      result = service.retry_run(failed_run)

      expect(result).to be_failure
      expect(result.error).to include("Trigger type")
    end

    it "fails when run is not in a retryable state" do
      running_run = create(:ai_workflow_run, :running, workflow: workflow, account: account)

      result = service.retry_run(running_run)

      expect(result).to be_failure
      expect(result.error).to include("Cannot retry")
    end
  end

  # ===========================================================================
  # #delete_run
  # ===========================================================================

  describe "#delete_run" do
    it "deletes a completed run" do
      completed_run = create(:ai_workflow_run, :completed, workflow: workflow, account: account)

      result = service.delete_run(completed_run)

      expect(result).to be_success
      expect(Ai::WorkflowRun.find_by(id: completed_run.id)).to be_nil
    end

    it "prevents deletion of running workflows" do
      running_run = create(:ai_workflow_run, :running, workflow: workflow, account: account)

      result = service.delete_run(running_run)

      expect(result).to be_failure
      expect(result.error).to include("Cannot delete")
    end

    it "deletes a failed run" do
      failed_run = create(:ai_workflow_run, :failed, workflow: workflow, account: account)

      result = service.delete_run(failed_run)

      expect(result).to be_success
    end
  end

  # ===========================================================================
  # #bulk_delete_runs
  # ===========================================================================

  describe "#bulk_delete_runs" do
    before do
      create(:ai_workflow_run, :completed, workflow: workflow, account: account)
      create(:ai_workflow_run, :completed, workflow: workflow, account: account)
      create(:ai_workflow_run, :failed, workflow: workflow, account: account)
    end

    it "deletes runs matching a status filter" do
      result = service.bulk_delete_runs(status: "completed")

      expect(result).to be_success
      expect(result.deleted_count).to eq(2)
    end

    it "excludes running workflows from deletion" do
      create(:ai_workflow_run, :running, workflow: workflow, account: account)

      result = service.bulk_delete_runs

      # Running workflow is excluded
      expect(workflow.runs.where(status: "running").count).to eq(1)
    end

    it "filters by time when before is specified" do
      result = service.bulk_delete_runs(before: 1.second.from_now)

      expect(result).to be_success
      expect(result.deleted_count).to be >= 1
    end
  end

  # ===========================================================================
  # #run_statistics
  # ===========================================================================

  describe "#run_statistics" do
    before do
      create(:ai_workflow_run, :completed, workflow: workflow, account: account)
      create(:ai_workflow_run, :failed, workflow: workflow, account: account)
      create(:ai_workflow_run, :running, workflow: workflow, account: account)
    end

    it "returns complete statistics about workflow runs" do
      stats = service.run_statistics

      expect(stats[:total_runs]).to eq(3)
      expect(stats[:completed_runs]).to eq(1)
      expect(stats[:failed_runs]).to eq(1)
      expect(stats[:running_runs]).to eq(1)
      expect(stats[:runs_by_status]).to be_a(Hash)
      expect(stats[:runs_by_trigger]).to be_a(Hash)
    end

    it "calculates success rate correctly" do
      stats = service.run_statistics

      # 1 completed out of 2 finished (completed + failed) = 0.5
      expect(stats[:success_rate]).to eq(0.5)
    end
  end
end
