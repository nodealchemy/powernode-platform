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

    # G13: loop-readiness preflight — a loop with no objective gate can't start.
    context "when the readiness preflight fails (no objective gate)" do
      let(:loop_status) { "pending" }

      before do
        create(:ai_ralph_task, ralph_loop: ralph_loop, status: "pending")
        ralph_loop.update!(total_tasks: 1, configuration: { "real_test_execution" => false })
      end

      it "refuses to start and stays pending" do
        result = service.start_loop

        expect(result[:success]).to be false
        expect(result[:error]).to match(/readiness preflight/i)
        expect(result[:failures].join).to match(/objective verification gate/i)
        expect(ralph_loop.reload.status).to eq("pending")
      end

      it "starts (with a warning) once the missing gate is acknowledged" do
        ralph_loop.update!(configuration: { "real_test_execution" => false, "acknowledge_no_gate" => true })
        result = service.start_loop

        expect(result[:success]).to be true
        expect(ralph_loop.reload.status).to eq("running")
        expect(result[:warnings].join).to match(/acknowledge/i)
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

    context "when an in-progress task is awaiting async test results" do
      let!(:awaiting_task) { create(:ai_ralph_task, :in_progress, ralph_loop: ralph_loop) }
      let!(:pending_task) { create(:ai_ralph_task, :pending, ralph_loop: ralph_loop, priority: 10, position: 2) }

      before do
        create(:ai_ralph_iteration, ralph_loop: ralph_loop, ralph_task: awaiting_task,
               iteration_number: 1, check_results: { "awaiting_test_result" => true })
      end

      it "skips the awaiting task and picks the next pending one (no re-run mid-test)" do
        expect(service.select_next_task).to eq(pending_task)
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

    # "blocked" is overloaded: it also means "parked for operator/human
    # review" (scope-guardrail block, human-review queue). update_blocked_tasks
    # runs from select_next_task on every tick and must not silently un-park
    # those tasks just because their dependencies happen to be satisfied.
    context "when a task is blocked for scope-guardrail review (not a dependency block)" do
      let!(:guardrail_blocked) do
        create(:ai_ralph_task, ralph_loop: ralph_loop, task_key: "task_1", status: "blocked",
               metadata: { "blocked_for" => "review" },
               error_message: "[scope-guardrail] touched payments/ — parked for human review")
      end

      it "does not unblock the task back to pending" do
        service.select_next_task
        expect(guardrail_blocked.reload.status).to eq("blocked")
      end

      it "is never returned as the next task" do
        expect(service.select_next_task).to be_nil
      end
    end

    context "when a task is blocked awaiting human review" do
      let!(:human_review_blocked) do
        create(:ai_ralph_task, ralph_loop: ralph_loop, task_key: "task_1", status: "blocked",
               metadata: { "blocked_for" => "review" }, error_message: "Awaiting human review")
      end

      it "does not unblock the task back to pending" do
        service.select_next_task
        expect(human_review_blocked.reload.status).to eq("blocked")
      end
    end

    context "when a legacy review-parked task has no blocked_for stamp (pre-fix rows)" do
      let!(:legacy_guardrail_blocked) do
        create(:ai_ralph_task, ralph_loop: ralph_loop, task_key: "task_1", status: "blocked",
               error_message: "[scope-guardrail] touched auth/ — parked for human review")
      end

      it "still does not unblock the task back to pending" do
        service.select_next_task
        expect(legacy_guardrail_blocked.reload.status).to eq("blocked")
      end
    end

    context "when a dependency-blocked task's dependency is satisfied" do
      let!(:passed_dep) { create(:ai_ralph_task, ralph_loop: ralph_loop, task_key: "task_1", status: "passed") }
      let!(:dependency_blocked) do
        create(:ai_ralph_task, ralph_loop: ralph_loop, task_key: "task_2", status: "blocked",
               dependencies: ["task_1"], metadata: { "blocked_for" => "dependency" },
               error_message: "Waiting for: task_1")
      end

      it "unblocks the task back to pending (existing behavior preserved)" do
        expect(service.select_next_task).to eq(dependency_blocked)
        expect(dependency_blocked.reload.status).to eq("pending")
      end
    end

    context "when a pending task has execution_type human" do
      let!(:human_task) do
        create(:ai_ralph_task, :pending, ralph_loop: ralph_loop, task_key: "task_1",
               execution_type: "human", priority: 10)
      end
      let!(:agent_task) do
        create(:ai_ralph_task, :pending, ralph_loop: ralph_loop, task_key: "task_2",
               execution_type: "agent", priority: 1)
      end

      it "never selects the human task, even at higher priority" do
        expect(service.select_next_task).to eq(agent_task)
      end
    end

    context "when only a human-execution-type task is available" do
      let!(:human_task) do
        create(:ai_ralph_task, :pending, ralph_loop: ralph_loop, task_key: "task_1", execution_type: "human")
      end

      it "returns nil rather than selecting the human task" do
        expect(service.select_next_task).to be_nil
      end
    end
  end

  # ===========================================================================
  # real test execution dispatch (Phase A4)
  # ===========================================================================

  describe "real test execution dispatch" do
    let(:loop_status) { "running" }
    let(:task) { create(:ai_ralph_task, :in_progress, ralph_loop: ralph_loop) }
    let(:iteration) do
      create(:ai_ralph_iteration, :running, ralph_loop: ralph_loop, ralph_task: task, iteration_number: 1)
    end
    let(:result) { { output: "did the work", checks_passed: true, commit_sha: "abc123", tokens: {}, cost: 0 } }

    before { allow(::WorkerJobService).to receive(:enqueue_ai_test_execution).and_return("success" => true) }

    context "when real_test_execution is enabled with a command and a commit was made" do
      before do
        ralph_loop.update!(repository_url: "https://git.example.com/acme/widget.git",
                           configuration: { "real_test_execution" => true,
                                            "test_command" => "bundle exec rspec",
                                            "test_framework" => "rspec" })
      end

      it "dispatches a sandboxed test run and parks the task instead of passing it" do
        service.send(:process_successful_iteration, iteration, task, result)

        expect(::WorkerJobService).to have_received(:enqueue_ai_test_execution).with(
          hash_including(ralph_loop_id: ralph_loop.id, ralph_iteration_id: iteration.id,
                         repository: "acme/widget", command: "bundle exec rspec", framework: "rspec")
        )
        expect(task.reload.status).to eq("in_progress")
        expect(iteration.reload.check_results["awaiting_test_result"]).to be true
      end
    end

    context "when left at the default (G1: the gate is opt-out) and a commit was made" do
      before do
        # No real_test_execution / test_command in configuration — the gate is ON
        # by default and the worker auto-detects the framework (command: nil).
        ralph_loop.update!(repository_url: "https://git.example.com/acme/widget.git")
      end

      it "dispatches a sandboxed test run (command nil ⇒ auto-detect) and parks the task" do
        service.send(:process_successful_iteration, iteration, task, result)

        expect(::WorkerJobService).to have_received(:enqueue_ai_test_execution).with(
          hash_including(ralph_loop_id: ralph_loop.id, ralph_iteration_id: iteration.id,
                         repository: "acme/widget", command: nil)
        )
        expect(task.reload.status).to eq("in_progress")
        expect(iteration.reload.check_results["awaiting_test_result"]).to be true
      end
    end

    context "when real_test_execution is explicitly disabled (opt-out)" do
      before { ralph_loop.update!(configuration: { "real_test_execution" => false }) }

      it "passes the task immediately and never dispatches a test run" do
        service.send(:process_successful_iteration, iteration, task, result)

        expect(::WorkerJobService).not_to have_received(:enqueue_ai_test_execution)
        expect(task.reload.status).to eq("passed")
      end
    end
  end

  # ===========================================================================
  # inc6: routing-decision outcome feedback (benefit measurement). When the Ralph
  # seam resolved a governed tier decision, its id is threaded onto the executor
  # result; the iteration-completion path feeds success/cost/tokens back onto the
  # decision via RoutingDecision#record_outcome!.
  # ===========================================================================

  describe "routing-decision outcome recording" do
    let(:loop_status) { "running" }
    let(:task) { create(:ai_ralph_task, :in_progress, ralph_loop: ralph_loop) }
    let(:iteration) do
      create(:ai_ralph_iteration, :running, ralph_loop: ralph_loop, ralph_task: task, iteration_number: 1)
    end
    let(:decision) do
      create(:ai_routing_decision, account: account, model_tier: "reasoning", outcome: nil,
             rationale: { "decision" => "escalate" })
    end

    before { ralph_loop.update!(configuration: { "real_test_execution" => false }) }

    it "records a succeeded outcome (with cost/tokens) on a successful iteration" do
      result = { success: true, output: "done", checks_passed: true,
                 tokens: { input: 100, output: 50 }, cost: 0.004, routing_decision_id: decision.id }

      service.send(:process_successful_iteration, iteration, task, result)

      decision.reload
      expect(decision.outcome).to eq("succeeded")
      expect(decision.actual_tokens_used).to eq(150)
      expect(decision.actual_cost_usd).to be_within(0.0001).of(0.004)
      expect(decision.actual_latency_ms).to be_present
      # Latency semantics tag: this seam records whole-iteration duration.
      expect(decision.rationale["latency_seam"]).to eq("ralph_iteration")
    end

    it "records a failed outcome on a failed iteration" do
      result = { success: false, error: "boom", error_code: "E1",
                 tokens: { input: 10, output: 0 }, cost: 0, routing_decision_id: decision.id }

      service.send(:process_failed_iteration, iteration, task, result)

      expect(decision.reload.outcome).to eq("failed")
    end

    it "no-ops when the result carries no routing decision id (gate OFF path)" do
      result = { success: true, output: "done", checks_passed: true, tokens: {}, cost: 0 }

      expect { service.send(:process_successful_iteration, iteration, task, result) }.not_to raise_error
      expect(decision.reload.outcome).to be_nil
    end
  end

  # ===========================================================================
  # G3: semantic maker/checker gate (separate-model evaluator) wired into the
  # task-completion path. Composes WITH the G1 real-test gate.
  # ===========================================================================

  describe "maker/checker semantic gate (G3)" do
    let(:loop_status) { "running" }
    let(:task) { create(:ai_ralph_task, :in_progress, ralph_loop: ralph_loop) }
    let(:iteration) do
      create(:ai_ralph_iteration, :running, ralph_loop: ralph_loop, ralph_task: task, iteration_number: 1)
    end
    let(:result) { { output: "did the work", checks_passed: true, commit_sha: "abc123", tokens: {}, cost: 0 } }
    let(:evaluator) { instance_double(Ai::Reasoning::OutputEvaluatorService) }
    # Stub the policy so the wiring test is isolated from model-tier selection
    # (the policy itself is unit-tested separately). A distinct checker model
    # satisfies the self-review ban.
    let(:policy) do
      instance_double(
        Ai::Ralph::MakerCheckerPolicy,
        enabled?: true, distinct_checker?: true,
        maker_model: "cheap-maker", checker_model: "strong-checker",
        checker_agent_id: agent.id, criteria: []
      )
    end

    before do
      allow(::WorkerJobService).to receive(:enqueue_ai_test_execution).and_return("success" => true)
      allow(Ai::Ralph::MakerCheckerPolicy).to receive(:new).and_return(policy)
      # STUB the LLM evaluator — no real LLM call happens.
      allow(Ai::Reasoning::OutputEvaluatorService).to receive(:new).and_return(evaluator)
    end

    context "when the checker returns reject (real-test gate ON)" do
      before do
        ralph_loop.update!(repository_url: "https://git.example.com/acme/widget.git",
                           configuration: { "maker_checker" => true, "real_test_execution" => true })
        allow(evaluator).to receive(:evaluate).and_return(
          { verdict: "reject", scores: { accuracy: 0.1 }, feedback: "fundamentally flawed" }
        )
      end

      it "does NOT pass the task, records the verdict, and short-circuits the test gate" do
        service.send(:process_successful_iteration, iteration, task, result)

        expect(task.reload.status).to eq("in_progress")
        expect(::WorkerJobService).not_to have_received(:enqueue_ai_test_execution)
        expect(iteration.reload.check_results["evaluator_verdict"]).to eq("reject")
        expect(iteration.check_results["evaluator_feedback"]).to eq("fundamentally flawed")
        expect(iteration.check_results["checker_model"]).to eq("strong-checker")
      end
    end

    context "when the checker returns revise" do
      before do
        ralph_loop.update!(configuration: { "maker_checker" => true, "real_test_execution" => false })
        allow(evaluator).to receive(:evaluate).and_return(
          { verdict: "revise", scores: {}, feedback: "fixable issues" }
        )
      end

      it "keeps the task for retry (not passed)" do
        service.send(:process_successful_iteration, iteration, task, result)

        expect(task.reload.status).to eq("in_progress")
        expect(iteration.reload.check_results["evaluator_verdict"]).to eq("revise")
      end
    end

    context "when the checker returns pass (real-test gate OFF)" do
      before do
        ralph_loop.update!(configuration: { "maker_checker" => true, "real_test_execution" => false })
        allow(evaluator).to receive(:evaluate).and_return(
          { verdict: "pass", scores: { accuracy: 0.95 }, feedback: "looks good" }
        )
      end

      it "passes the task and records the verdict" do
        service.send(:process_successful_iteration, iteration, task, result)

        expect(task.reload.status).to eq("passed")
        expect(iteration.reload.check_results["evaluator_verdict"]).to eq("pass")
      end
    end

    context "when the checker returns pass and the real-test gate is ON (composition)" do
      before do
        ralph_loop.update!(repository_url: "https://git.example.com/acme/widget.git",
                           configuration: { "maker_checker" => true, "real_test_execution" => true })
        allow(evaluator).to receive(:evaluate).and_return({ verdict: "pass", scores: {}, feedback: "ok" })
      end

      it "proceeds to the G1 sandboxed-test gate (dispatches tests, task parked)" do
        service.send(:process_successful_iteration, iteration, task, result)

        expect(::WorkerJobService).to have_received(:enqueue_ai_test_execution)
        expect(task.reload.status).to eq("in_progress")
        expect(iteration.reload.check_results["awaiting_test_result"]).to be true
        expect(iteration.check_results["evaluator_verdict"]).to eq("pass")
      end
    end

    context "when the self-review ban cannot be satisfied (no distinct checker)" do
      before do
        ralph_loop.update!(configuration: { "maker_checker" => true, "real_test_execution" => false })
        allow(policy).to receive(:distinct_checker?).and_return(false)
      end

      it "skips the checker entirely and falls through to the existing gate" do
        service.send(:process_successful_iteration, iteration, task, result)

        expect(Ai::Reasoning::OutputEvaluatorService).not_to have_received(:new)
        expect(task.reload.status).to eq("passed")
      end
    end
  end

  describe "maker/checker disabled (default — real policy, evaluator never invoked)" do
    let(:loop_status) { "running" }
    let(:task) { create(:ai_ralph_task, :in_progress, ralph_loop: ralph_loop) }
    let(:iteration) do
      create(:ai_ralph_iteration, :running, ralph_loop: ralph_loop, ralph_task: task, iteration_number: 1)
    end
    let(:result) { { output: "did the work", checks_passed: true, commit_sha: "abc123", tokens: {}, cost: 0 } }

    before do
      allow(::WorkerJobService).to receive(:enqueue_ai_test_execution).and_return("success" => true)
      allow(Ai::Reasoning::OutputEvaluatorService).to receive(:new).and_call_original
      # Default config (no maker_checker key); disable the real-test gate so the
      # task resolves via checks_passed exactly as before this increment.
      ralph_loop.update!(configuration: { "real_test_execution" => false })
    end

    it "never constructs the evaluator and passes the task as before" do
      service.send(:process_successful_iteration, iteration, task, result)

      expect(Ai::Reasoning::OutputEvaluatorService).not_to have_received(:new)
      expect(task.reload.status).to eq("passed")
    end
  end

  # ===========================================================================
  # G3 follow-up: the maker/checker reviews the REAL unified diff (scrubbed,
  # size-capped) when the executor captured one, and falls back to the
  # output-text + changed-files summary when it didn't.
  # ===========================================================================

  describe "maker/checker diff review (G3 follow-up)" do
    let(:loop_status) { "running" }
    let(:task) { create(:ai_ralph_task, :in_progress, ralph_loop: ralph_loop) }
    let(:iteration) do
      create(:ai_ralph_iteration, :running, ralph_loop: ralph_loop, ralph_task: task, iteration_number: 1)
    end
    let(:evaluator) { instance_double(Ai::Reasoning::OutputEvaluatorService) }
    let(:policy) do
      instance_double(
        Ai::Ralph::MakerCheckerPolicy,
        enabled?: true, distinct_checker?: true,
        maker_model: "cheap-maker", checker_model: "strong-checker",
        checker_agent_id: agent.id, criteria: []
      )
    end
    # Capture the exact review input the (stubbed) evaluator is handed.
    let(:captured) { {} }

    before do
      ralph_loop.update!(configuration: { "maker_checker" => true, "real_test_execution" => false })
      allow(Ai::Ralph::MakerCheckerPolicy).to receive(:new).and_return(policy)
      allow(Ai::Reasoning::OutputEvaluatorService).to receive(:new).and_return(evaluator)
      allow(evaluator).to receive(:evaluate) do |**kwargs|
        captured[:output] = kwargs[:output]
        { verdict: "pass", scores: {}, feedback: "ok" }
      end
    end

    context "when the executor provides a real unified diff (with a planted secret)" do
      let(:result) do
        {
          output: "did the work", checks_passed: true, commit_sha: "abc123",
          diff: "diff --git a/app/x.rb b/app/x.rb\n+api_key=\"SUPERSECRETVALUE123\"\n+puts :ok\n",
          file_changes: ["app/x.rb"], tokens: {}, cost: 0
        }
      end

      it "feeds the diff to the checker, scrubbed of the secret, not the file-list summary" do
        service.send(:process_successful_iteration, iteration, task, result)

        review = captured[:output]
        expect(review).to include("Unified diff:")
        expect(review).to include("diff --git a/app/x.rb b/app/x.rb")
        expect(review).to include("puts :ok")
        # G15 scrub: the planted secret value never reaches the evaluator.
        expect(review).not_to include("SUPERSECRETVALUE123")
        expect(review).to include("[REDACTED]")
        # Prefer the diff over the changed-files summary when a diff is present.
        expect(review).not_to include("Changed files:")
      end
    end

    context "when the executor provides no diff (fallback)" do
      let(:result) do
        {
          output: "did the work", checks_passed: true, commit_sha: "abc123",
          file_changes: ["app/x.rb"], tokens: {}, cost: 0
        }
      end

      it "falls back to the output text + commit + changed-files summary (no regression)" do
        service.send(:process_successful_iteration, iteration, task, result)

        review = captured[:output]
        expect(review).to include("did the work")
        expect(review).to include("Commit: abc123")
        expect(review).to include("Changed files: app/x.rb")
        expect(review).not_to include("Unified diff:")
      end
    end
  end

  # ===========================================================================
  # G10: scope guardrail on the platform executor path. A commit touching a
  # protected path is BLOCKED for human review (never auto-passed), composing
  # with the G1 test gate and G3 maker/checker.
  # ===========================================================================

  describe "scope guardrail (G10 platform path)" do
    let(:loop_status) { "running" }
    let(:task) { create(:ai_ralph_task, :in_progress, ralph_loop: ralph_loop) }
    let(:iteration) do
      create(:ai_ralph_iteration, :running, ralph_loop: ralph_loop, ralph_task: task, iteration_number: 1)
    end

    before { allow(::WorkerJobService).to receive(:enqueue_ai_test_execution).and_return("success" => true) }

    context "when a commit touches a protected path and the real-test gate is ON" do
      let(:result) do
        { output: "patched billing", checks_passed: true, commit_sha: "abc123",
          file_changes: ["app/services/payments/charge_service.rb"], tokens: {}, cost: 0 }
      end

      before do
        ralph_loop.update!(repository_url: "https://git.example.com/acme/widget.git",
                           configuration: { "real_test_execution" => true })
      end

      it "BLOCKS the task (short-circuits the test gate) and records the guardrail verdict" do
        service.send(:process_successful_iteration, iteration, task, result)

        expect(task.reload.status).to eq("blocked")
        expect(::WorkerJobService).not_to have_received(:enqueue_ai_test_execution)
        verdict = iteration.reload.check_results["scope_guardrail"]
        expect(verdict["blocked"]).to be true
        expect(verdict["violations"].first["file"]).to eq("app/services/payments/charge_service.rb")
        expect(iteration.reload.check_results["awaiting_test_result"]).to be_nil
      end
    end

    context "when the loop has a campaign attached" do
      let(:campaign) { create(:ai_campaign, account: account, decision_authority: "autonomous") }
      let(:result) do
        { output: "touched secrets", checks_passed: true, commit_sha: "abc123",
          file_changes: ["config/credentials.yml.enc"], tokens: {}, cost: 0 }
      end

      before { ralph_loop.update!(campaign: campaign, configuration: { "real_test_execution" => false }) }

      it "parks an operator question on the campaign and blocks the task" do
        expect { service.send(:process_successful_iteration, iteration, task, result) }
          .to change { campaign.reload.parked_questions.count }.by(1)
        expect(task.reload.status).to eq("blocked")
      end
    end

    context "when the commit touches only unprotected paths" do
      let(:result) do
        { output: "ok", checks_passed: true, commit_sha: "abc123",
          file_changes: ["app/models/widget.rb"], tokens: {}, cost: 0 }
      end

      before { ralph_loop.update!(configuration: { "real_test_execution" => false }) }

      it "does not block — passes as today (composes with the existing gates)" do
        service.send(:process_successful_iteration, iteration, task, result)

        expect(task.reload.status).to eq("passed")
        expect(iteration.reload.check_results["scope_guardrail"]).to be_nil
      end
    end

    context "when no commit was made (even if a protected path appears in file_changes)" do
      let(:result) do
        { output: "investigated only", checks_passed: true, commit_sha: nil,
          file_changes: ["app/services/payments/charge_service.rb"], tokens: {}, cost: 0 }
      end

      before { ralph_loop.update!(configuration: { "real_test_execution" => false }) }

      it "does not evaluate the guardrail (no commit ⇒ nothing lands)" do
        service.send(:process_successful_iteration, iteration, task, result)

        expect(iteration.reload.check_results["scope_guardrail"]).to be_nil
        expect(task.reload.status).to eq("passed")
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

    # G5: runtime resource caps stop the platform executor mid-run too — the same
    # predicate the dev-loop pull path uses.
    context "when a runtime cap is exceeded" do
      before { create(:ai_ralph_task, :pending, ralph_loop: ralph_loop) }

      it "stops the loop on a wall-clock timeout" do
        ralph_loop.update!(started_at: 2.hours.ago, configuration: { "max_wall_clock_seconds" => 60 })

        result = service.run_iteration

        expect(result[:success]).to be true
        expect(result[:stopped]).to be true
        expect(result[:reason]).to eq("wall_clock_exceeded")
        expect(ralph_loop.reload.status).to eq("completed")
      end

      it "stops a metered loop over its token cap" do
        ralph_loop.update!(driver_kind: "platform_agent", configuration: { "max_tokens" => 1000 })
        create(:ai_ralph_iteration, ralph_loop: ralph_loop, iteration_number: 1,
                                    tokens_input: 700, tokens_output: 700)

        result = service.run_iteration

        expect(result[:stopped]).to be true
        expect(result[:reason]).to eq("token_cap_exceeded")
        expect(ralph_loop.reload.status).to eq("completed")
      end
    end
  end

  # ===========================================================================
  # IMP-aa8a2f58e01e: the trust-fall pass path (real-test gate OFF) adjudicates
  # the run's own transcript instead of trusting result[:checks_passed].
  # Verified tally → checks_passed true; no machine evidence → pass but record
  # attested (false); transcript CONTRADICTS the claim → do not pass, retry.
  # ===========================================================================

  describe "transcript evidence adjudication on the direct pass path" do
    let(:loop_status) { "running" }
    let(:task) { create(:ai_ralph_task, :in_progress, ralph_loop: ralph_loop) }
    let(:iteration) do
      create(:ai_ralph_iteration, :running, ralph_loop: ralph_loop, ralph_task: task, iteration_number: 1)
    end

    before { ralph_loop.update!(configuration: { "real_test_execution" => false }) }

    def run!(output)
      result = { output: output, checks_passed: true, commit_sha: "abc123", tokens: {}, cost: 0 }
      service.send(:process_successful_iteration, iteration, task, result)
    end

    it "records checks_passed true when the transcript carries a green tally" do
      run!("ran the suite\n12 examples, 0 failures")
      expect(task.reload.status).to eq("passed")
      expect(iteration.reload.checks_passed).to be(true)
    end

    it "passes but records attested (checks_passed false) when the transcript has no machine evidence" do
      run!("did the work, everything looks good")
      expect(task.reload.status).to eq("passed")
      expect(iteration.reload.checks_passed).to be(false)
    end

    it "does NOT pass when the transcript contradicts the claimed pass" do
      run!("ran the suite\n12 examples, 3 failures")
      expect(task.reload.status).to eq("in_progress")
      expect(iteration.reload.checks_passed).to be(false)
    end
  end
end
