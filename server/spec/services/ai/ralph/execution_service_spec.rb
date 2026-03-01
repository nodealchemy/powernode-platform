# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Ralph::ExecutionService, type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:provider) { create(:ai_provider, account: account) }
  let(:agent) { create(:ai_agent, account: account, provider: provider) }

  let(:ralph_loop) do
    create(:ai_ralph_loop, account: account, default_agent: agent, status: loop_status)
  end
  let(:loop_status) { "pending" }

  subject(:service) { described_class.new(ralph_loop: ralph_loop, account: account, user: user) }

  # ===========================================================================
  # #start_loop
  # ===========================================================================

  describe "#start_loop" do
    context "when loop is pending with tasks" do
      let(:loop_status) { "pending" }

      before do
        create(:ai_ralph_task, ralph_loop: ralph_loop, status: "pending")
        ralph_loop.update!(total_tasks: 1)
      end

      it "starts the loop and returns success" do
        result = service.start_loop

        expect(result[:success]).to be true
        expect(result[:message]).to eq("Loop started successfully")
        expect(ralph_loop.reload.status).to eq("running")
      end
    end

    context "when loop has no tasks" do
      let(:loop_status) { "pending" }

      it "returns error when no tasks are defined" do
        result = service.start_loop

        expect(result[:success]).to be false
        expect(result[:error]).to include("No tasks defined")
      end
    end

    context "when loop is not in pending status" do
      let(:loop_status) { "running" }

      it "returns error" do
        result = service.start_loop

        expect(result[:success]).to be false
        expect(result[:error]).to include("not in pending status")
      end
    end

    context "when loop has blocked tasks with satisfied dependencies" do
      let(:loop_status) { "pending" }

      before do
        task1 = create(:ai_ralph_task, ralph_loop: ralph_loop, task_key: "task_1", status: "passed")
        create(:ai_ralph_task, ralph_loop: ralph_loop, task_key: "task_2", status: "blocked",
               dependencies: ["task_1"], error_message: "Waiting for: task_1")
        ralph_loop.update!(total_tasks: 2)
      end

      it "unblocks tasks whose dependencies are satisfied" do
        service.start_loop
        blocked_count = ralph_loop.ralph_tasks.blocked.count

        expect(blocked_count).to eq(0)
      end
    end
  end

  # ===========================================================================
  # #pause_loop
  # ===========================================================================

  describe "#pause_loop" do
    context "when loop is running" do
      let(:loop_status) { "running" }

      it "pauses the loop" do
        result = service.pause_loop

        expect(result[:success]).to be true
        expect(result[:message]).to eq("Loop paused successfully")
        expect(ralph_loop.reload.status).to eq("paused")
      end
    end

    context "when loop is not running" do
      let(:loop_status) { "pending" }

      it "returns error" do
        result = service.pause_loop

        expect(result[:success]).to be false
        expect(result[:error]).to include("not running")
      end
    end

    context "when run_all is active" do
      let(:loop_status) { "running" }

      before do
        ralph_loop.update!(configuration: { "run_all_active" => true })
      end

      it "deactivates run_all flag" do
        service.pause_loop

        expect(ralph_loop.reload.configuration["run_all_active"]).to be false
      end
    end
  end

  # ===========================================================================
  # #resume_loop
  # ===========================================================================

  describe "#resume_loop" do
    context "when loop is paused" do
      let(:loop_status) { "paused" }

      it "resumes the loop" do
        result = service.resume_loop

        expect(result[:success]).to be true
        expect(result[:message]).to eq("Loop resumed successfully")
        expect(ralph_loop.reload.status).to eq("running")
      end
    end

    context "when loop is not paused" do
      let(:loop_status) { "running" }

      it "returns error" do
        result = service.resume_loop

        expect(result[:success]).to be false
        expect(result[:error]).to include("not paused")
      end
    end
  end

  # ===========================================================================
  # #cancel_loop
  # ===========================================================================

  describe "#cancel_loop" do
    context "when loop is running" do
      let(:loop_status) { "running" }

      it "cancels the loop" do
        result = service.cancel_loop(reason: "User requested")

        expect(result[:success]).to be true
        expect(result[:message]).to eq("Loop cancelled")
        expect(ralph_loop.reload.status).to eq("cancelled")
      end
    end

    context "when loop is already completed" do
      let(:loop_status) { "completed" }

      it "returns error" do
        result = service.cancel_loop

        expect(result[:success]).to be false
        expect(result[:error]).to include("cannot be cancelled")
      end
    end
  end

  # ===========================================================================
  # #select_next_task
  # ===========================================================================

  describe "#select_next_task" do
    let(:loop_status) { "running" }

    context "when there is an in-progress task" do
      let!(:in_progress_task) do
        create(:ai_ralph_task, :in_progress, ralph_loop: ralph_loop)
      end
      let!(:pending_task) do
        create(:ai_ralph_task, :pending, ralph_loop: ralph_loop, priority: 10)
      end

      it "returns the in-progress task first" do
        expect(service.select_next_task).to eq(in_progress_task)
      end
    end

    context "when there are only pending tasks" do
      let!(:low_priority) do
        create(:ai_ralph_task, :pending, ralph_loop: ralph_loop, priority: 1, position: 1)
      end
      let!(:high_priority) do
        create(:ai_ralph_task, :pending, ralph_loop: ralph_loop, priority: 10, position: 2)
      end

      it "returns the highest priority task" do
        expect(service.select_next_task).to eq(high_priority)
      end
    end

    context "when a task has unsatisfied dependencies" do
      let!(:dep_task) do
        create(:ai_ralph_task, :pending, ralph_loop: ralph_loop, task_key: "task_1", priority: 1, position: 1)
      end
      let!(:blocked_task) do
        create(:ai_ralph_task, :pending, ralph_loop: ralph_loop, task_key: "task_2",
               priority: 10, position: 2, dependencies: ["task_1"])
      end

      it "skips tasks with unsatisfied dependencies" do
        expect(service.select_next_task).to eq(dep_task)
      end
    end

    context "when no tasks are available" do
      it "returns nil" do
        expect(service.select_next_task).to be_nil
      end
    end
  end

  # ===========================================================================
  # #run_all
  # ===========================================================================

  describe "#run_all" do
    let(:loop_status) { "running" }

    before do
      allow(WorkerJobService).to receive(:enqueue_ai_ralph_loop_run_all)
    end

    it "sets run_all_active flag and enqueues job" do
      result = service.run_all

      expect(result[:success]).to be true
      expect(result[:message]).to eq("Run All started")
      expect(ralph_loop.reload.configuration["run_all_active"]).to be true
      expect(WorkerJobService).to have_received(:enqueue_ai_ralph_loop_run_all).with(ralph_loop.id, stop_on_error: true)
    end

    context "when run_all is already active" do
      before do
        ralph_loop.update!(configuration: { "run_all_active" => true })
      end

      it "returns error" do
        result = service.run_all

        expect(result[:success]).to be false
        expect(result[:error]).to include("already active")
      end
    end

    context "when loop is not running" do
      let(:loop_status) { "paused" }

      it "returns error" do
        result = service.run_all

        expect(result[:success]).to be false
        expect(result[:error]).to include("not running")
      end
    end
  end

  # ===========================================================================
  # #stop_run_all
  # ===========================================================================

  describe "#stop_run_all" do
    let(:loop_status) { "running" }

    before do
      ralph_loop.update!(configuration: { "run_all_active" => true })
    end

    it "deactivates the run_all flag" do
      result = service.stop_run_all

      expect(result[:success]).to be true
      expect(ralph_loop.reload.configuration["run_all_active"]).to be false
    end
  end

  # ===========================================================================
  # #parse_prd
  # ===========================================================================

  describe "#parse_prd" do
    let(:loop_status) { "pending" }

    context "with array format PRD data" do
      let(:prd_data) do
        [
          { "key" => "setup_db", "description" => "Set up database", "priority" => 10,
            "acceptance_criteria" => "DB runs migrations" },
          { "key" => "build_api", "description" => "Build API endpoints", "priority" => 5,
            "dependencies" => ["setup_db"] }
        ]
      end

      it "creates tasks from PRD array" do
        result = service.parse_prd(prd_data)

        expect(result[:success]).to be true
        expect(result[:tasks_created]).to eq(2)
        expect(ralph_loop.reload.total_tasks).to eq(2)
      end
    end

    context "with hash format containing tasks key" do
      let(:prd_data) do
        {
          "tasks" => [
            { "key" => "task_1", "description" => "First task" }
          ]
        }
      end

      it "creates tasks from the nested tasks array" do
        result = service.parse_prd(prd_data)

        expect(result[:success]).to be true
        expect(result[:tasks_created]).to eq(1)
      end
    end

    context "with single hash PRD" do
      let(:prd_data) do
        { "key" => "single_task", "description" => "A single task" }
      end

      it "creates a single task" do
        result = service.parse_prd(prd_data)

        expect(result[:success]).to be true
        expect(result[:tasks_created]).to eq(1)
      end
    end

    context "with blank data" do
      it "returns error" do
        result = service.parse_prd(nil)

        expect(result[:success]).to be false
        expect(result[:error]).to include("PRD data is required")
      end
    end

    context "when reparsing clears existing tasks" do
      before do
        create(:ai_ralph_task, ralph_loop: ralph_loop, task_key: "old_task")
      end

      let(:prd_data) do
        [{ "key" => "new_task", "description" => "New task" }]
      end

      it "replaces old tasks with new ones" do
        result = service.parse_prd(prd_data)

        expect(result[:success]).to be true
        expect(ralph_loop.ralph_tasks.pluck(:task_key)).to eq(["new_task"])
      end
    end
  end

  # ===========================================================================
  # #status
  # ===========================================================================

  describe "#status" do
    let(:loop_status) { "running" }

    before do
      create(:ai_ralph_task, :pending, ralph_loop: ralph_loop)
    end

    it "returns loop status with tasks and recent iterations" do
      result = service.status

      expect(result[:loop]).to be_a(Hash)
      expect(result[:tasks]).to be_an(Array)
      expect(result[:tasks].size).to eq(1)
      expect(result[:recent_iterations]).to be_an(Array)
    end
  end

  # ===========================================================================
  # #learnings
  # ===========================================================================

  describe "#learnings" do
    let(:loop_status) { "running" }

    context "with existing learnings" do
      before do
        ralph_loop.update!(learnings: [
          { "text" => "Use smaller functions", "iteration" => 1 },
          { "text" => "Test edge cases", "iteration" => 2 }
        ])
      end

      it "returns learnings grouped by iteration" do
        result = service.learnings

        expect(result[:total_count]).to eq(2)
        expect(result[:learnings].size).to eq(2)
        expect(result[:by_iteration]).to have_key(1)
        expect(result[:by_iteration]).to have_key(2)
      end
    end

    context "with no learnings" do
      it "returns empty structures" do
        result = service.learnings

        expect(result[:total_count]).to eq(0)
        expect(result[:learnings]).to eq([])
      end
    end
  end

  # ===========================================================================
  # #update_progress
  # ===========================================================================

  describe "#update_progress" do
    let(:loop_status) { "running" }

    it "updates the progress text" do
      result = service.update_progress("Working on task 3")

      expect(result[:success]).to be true
      expect(result[:progress_text]).to eq("Working on task 3")
      expect(ralph_loop.reload.progress_text).to eq("Working on task 3")
    end
  end

  # ===========================================================================
  # #run_iteration
  # ===========================================================================

  describe "#run_iteration" do
    let(:loop_status) { "running" }

    context "when loop is not running" do
      let(:loop_status) { "paused" }

      it "returns error" do
        result = service.run_iteration

        expect(result[:success]).to be false
        expect(result[:error]).to include("not running")
      end
    end

    context "when max iterations reached" do
      before do
        ralph_loop.update!(current_iteration: 10, max_iterations: 10)
        create(:ai_ralph_task, :pending, ralph_loop: ralph_loop)
      end

      it "fails the loop with max iterations error" do
        result = service.run_iteration

        expect(result[:success]).to be false
        expect(result[:error]).to include("Maximum iterations reached")
      end
    end

    context "when all tasks are completed" do
      before do
        create(:ai_ralph_task, :passed, ralph_loop: ralph_loop)
        ralph_loop.update!(total_tasks: 1, completed_tasks: 1)
      end

      it "completes the loop" do
        result = service.run_iteration

        expect(result[:success]).to be true
        expect(result[:completed]).to be true
        expect(ralph_loop.reload.status).to eq("completed")
      end
    end
  end
end
