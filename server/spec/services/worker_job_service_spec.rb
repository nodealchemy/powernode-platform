# frozen_string_literal: true

require "rails_helper"

# The per-account kill switch is enforced worker-side (AiSuspensionCheckConcern),
# but the worker only honors it when the enqueue payload carries account_id. Two
# jobs receive only a bare step_id / challenge_id, so WorkerJobService must resolve
# the owning account from the record and thread it into "args". Regression spec for
# IMP-7f395d55d15b (server side of the kill-switch completion).
RSpec.describe WorkerJobService do
  # Capture the payload sent to the worker without making a real HTTP request.
  def capture_payload
    payload = nil
    allow_any_instance_of(described_class).to receive(:make_worker_request) do |_instance, _method, _path, body|
      payload = body
      { "success" => true }
    end
    yield
    payload
  end

  describe ".enqueue_ai_goal_plan_step_execution" do
    let(:step_id) { "step-123" }
    let(:account_id) { "account-abc" }

    it "resolves account_id from the step's goal plan and threads it into args" do
      plan = double("Ai::GoalPlan", account_id: account_id)
      step = double("Ai::GoalPlanStep", plan: plan)
      allow(Ai::GoalPlanStep).to receive(:find_by).with(id: step_id).and_return(step)

      payload = capture_payload { described_class.enqueue_ai_goal_plan_step_execution(step_id) }

      expect(payload["args"]).to eq([ step_id, account_id ])
    end

    it "passes nil account_id when the step cannot be resolved (fail-open)" do
      allow(Ai::GoalPlanStep).to receive(:find_by).with(id: step_id).and_return(nil)

      payload = capture_payload { described_class.enqueue_ai_goal_plan_step_execution(step_id) }

      expect(payload["args"]).to eq([ step_id, nil ])
    end
  end

  describe ".enqueue_ai_test_execution" do
    it "dispatches AiTestExecutionJob with the iteration/repo/command payload on ai_execution" do
      payload = capture_payload do
        described_class.enqueue_ai_test_execution(
          ralph_loop_id: "loop-1", ralph_iteration_id: "iter-1",
          repository: "acme/widget", branch: "feature/x",
          command: "bundle exec rspec", framework: "rspec"
        )
      end

      expect(payload["job_class"]).to eq("AiTestExecutionJob")
      expect(payload["queue"]).to eq("ai_execution")
      expect(payload["args"].first).to include(
        "ralph_loop_id" => "loop-1", "ralph_iteration_id" => "iter-1",
        "repository" => "acme/widget", "branch" => "feature/x",
        "command" => "bundle exec rspec", "framework" => "rspec", "timeout_seconds" => 600
      )
    end
  end

  describe ".enqueue_mcp_monitoring_webhook" do
    it "dispatches Webhooks::MonitoringWebhookDeliveryJob with the raw url+payload on the webhooks queue" do
      payload = capture_payload do
        described_class.enqueue_mcp_monitoring_webhook("https://hooks.example.com/mcp", '{"event":"x"}')
      end

      expect(payload["job_class"]).to eq("Webhooks::MonitoringWebhookDeliveryJob")
      expect(payload["queue"]).to eq("webhooks")
      expect(payload["args"]).to eq([ "https://hooks.example.com/mcp", '{"event":"x"}' ])
    end
  end

  describe ".enqueue_ai_self_challenge" do
    let(:challenge_id) { "challenge-123" }
    let(:account_id) { "account-xyz" }

    it "resolves account_id from the challenge record and threads it into args" do
      challenge = double("Ai::SelfChallenge", account_id: account_id)
      allow(Ai::SelfChallenge).to receive(:find_by).with(id: challenge_id).and_return(challenge)

      payload = capture_payload { described_class.enqueue_ai_self_challenge(challenge_id) }

      expect(payload["args"]).to eq([ challenge_id, account_id ])
    end

    it "passes nil account_id when the challenge cannot be resolved (fail-open)" do
      allow(Ai::SelfChallenge).to receive(:find_by).with(id: challenge_id).and_return(nil)

      payload = capture_payload { described_class.enqueue_ai_self_challenge(challenge_id) }

      expect(payload["args"]).to eq([ challenge_id, nil ])
    end
  end
end
