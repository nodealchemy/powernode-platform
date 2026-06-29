# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiTestExecutionJob, type: :job do
  it_behaves_like "a base job", described_class

  let(:job) { described_class.new }
  let(:api_client_double) { double("BackendApiClient") }
  let(:checkout_handler) { double("CheckoutHandler") }
  let(:run_handler) { double("RunCommandHandler") }

  let(:args) do
    {
      "ralph_loop_id" => "loop-1",
      "ralph_iteration_id" => "iter-1",
      "repository" => "acme/widget",
      "branch" => "feature/x",
      "command" => "bundle exec rspec",
      "framework" => "rspec",
      "timeout_seconds" => 600
    }
  end

  before do
    # The step handlers are eager-loaded at worker runtime but not autoloaded in
    # the test env; define the constants here so the job's references resolve.
    # The splat initialize matches the job's `.new(api_client:, logger:)` under
    # verify_partial_doubles.
    stub_const("Devops::StepHandlers::CheckoutHandler", Class.new { def initialize(*, **); end })
    stub_const("Devops::StepHandlers::RunCommandHandler", Class.new { def initialize(*, **); end })
    allow(job).to receive(:api_client).and_return(api_client_double)
    allow_any_instance_of(BaseJob).to receive(:check_runaway_loop).and_return(nil)
    allow(Devops::StepHandlers::CheckoutHandler).to receive(:new).and_return(checkout_handler)
    allow(Devops::StepHandlers::RunCommandHandler).to receive(:new).and_return(run_handler)
    allow(api_client_double).to receive(:post).and_return("success" => true)
    allow(FileUtils).to receive(:rm_rf)
    allow(File).to receive(:directory?).and_return(false)
  end

  it "runs on the ai_execution queue" do
    expect(described_class.get_sidekiq_options["queue"]).to eq("ai_execution")
  end

  describe "#execute" do
    it "checks out the branch, runs the command, and posts the raw result back" do
      expect(checkout_handler).to receive(:execute).with(
        config: { "ref" => "feature/x" },
        context: { trigger_context: { repository: "acme/widget", branch: "feature/x" } },
        previous_outputs: {}
      ).and_return(outputs: { workspace: "/tmp/ws" })

      expect(run_handler).to receive(:execute).with(
        config: hash_including("command" => "bundle exec rspec", "continue_on_error" => true),
        context: { trigger_context: {} },
        previous_outputs: { "checkout" => { workspace: "/tmp/ws" } }
      ).and_return(outputs: { output: "5 examples, 0 failures", exit_code: 0 })

      job.execute(args)

      expect(api_client_double).to have_received(:post).with(
        "/api/v1/internal/ai/ralph_loops/loop-1/iterations/iter-1/test_results",
        hash_including(test_result: hash_including(exit_code: 0, framework: "rspec",
                                                   output: "5 examples, 0 failures", command: "bundle exec rspec"))
      )
    end

    it "passes a nonzero exit through (the server decides pass/fail)" do
      allow(checkout_handler).to receive(:execute).and_return(outputs: { workspace: "/tmp/ws" })
      allow(run_handler).to receive(:execute).and_return(outputs: { output: "1) boom", exit_code: 1 })

      job.execute(args)

      expect(api_client_double).to have_received(:post).with(
        anything, hash_including(test_result: hash_including(exit_code: 1))
      )
    end

    it "reports a failure when checkout raises (so the iteration resolves)" do
      allow(checkout_handler).to receive(:execute).and_raise(StandardError.new("clone denied"))

      job.execute(args)

      expect(api_client_double).to have_received(:post).with(
        anything, hash_including(test_result: hash_including(exit_code: 1, error: /clone denied/))
      )
    end

    it "no-ops without the required args" do
      job.execute("ralph_loop_id" => "x")
      expect(api_client_double).not_to have_received(:post)
    end

    it "cleans up the workspace afterwards" do
      allow(File).to receive(:directory?).with("/tmp/ws").and_return(true)
      allow(checkout_handler).to receive(:execute).and_return(outputs: { workspace: "/tmp/ws" })
      allow(run_handler).to receive(:execute).and_return(outputs: { output: "ok", exit_code: 0 })

      job.execute(args)

      expect(FileUtils).to have_received(:rm_rf).with("/tmp/ws")
    end
  end
end
