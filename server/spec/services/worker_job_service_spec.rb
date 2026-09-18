# frozen_string_literal: true

require "rails_helper"

# The per-account kill switch is enforced worker-side (AiSuspensionCheckConcern),
# but the worker only honors it when the enqueue payload carries account_id. These
# enqueue paths receive only a bare step_id / challenge_id / team_id, so
# WorkerJobService must resolve the owning account from the record and thread it
# into "args". Regression spec for IMP-7f395d55d15b (goal plan step / self
# challenge) and IMP-414ae01a5682 (team execution).
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

  describe ".enqueue_ai_team_execution" do
    let(:team_id) { "team-123" }
    let(:account_id) { "account-def" }

    it "resolves account_id from the team and threads it into the job payload" do
      team = double("Ai::AgentTeam", account_id: account_id)
      allow(Ai::AgentTeam).to receive(:find_by).with(id: team_id).and_return(team)

      payload = capture_payload do
        described_class.enqueue_ai_team_execution(team_id: team_id, user_id: "user-1", input: { "task" => "t" })
      end

      expect(payload["job_class"]).to eq("AiTeamExecutionJob")
      expect(payload["args"].first).to include(
        "team_id" => team_id, "user_id" => "user-1", "account_id" => account_id
      )
    end

    it "passes nil account_id when the team cannot be resolved (fail-open)" do
      allow(Ai::AgentTeam).to receive(:find_by).with(id: team_id).and_return(nil)

      payload = capture_payload do
        described_class.enqueue_ai_team_execution(team_id: team_id, user_id: "user-1")
      end

      expect(payload["args"].first).to include("account_id" => nil)
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

  describe ".enqueue_ai_webhook_delivery" do
    it "dispatches AiWebhookDeliveryJob with the execution id on the ai_agents queue" do
      payload = capture_payload { described_class.enqueue_ai_webhook_delivery("exec-123") }

      expect(payload["job_class"]).to eq("AiWebhookDeliveryJob")
      expect(payload["queue"]).to eq("ai_agents")
      expect(payload["args"]).to eq([ "exec-123" ])
      expect(payload["options"]).to eq({ "retry" => 2 })
    end
  end

  # IMP-f301fd6563d2: callers that need to distinguish "definitely not sent"
  # from "outcome unknown" (to decide whether an idempotency claim should be
  # released) depend on #make_worker_request raising the RIGHT subclass of
  # WorkerServiceError for each failure shape. Stubbed at the Net::HTTP
  # boundary so the real branching in #make_worker_request runs.
  describe "#make_worker_request error mapping" do
    let(:service) { described_class.new }
    let(:http_double) { instance_double(Net::HTTP) }

    before do
      allow(Net::HTTP).to receive(:new).and_return(http_double)
      allow(http_double).to receive(:use_ssl=)
      allow(http_double).to receive(:read_timeout=)
      allow(http_double).to receive(:open_timeout=)
      allow(described_class).to receive(:system_worker_jwt).and_return("jwt-token")
    end

    def stub_response(code:, body: nil)
      response = instance_double(Net::HTTPResponse, code: code.to_s, body: body)
      allow(http_double).to receive(:request).and_return(response)
    end

    def call_it
      service.make_worker_request("POST", "/api/v1/jobs", { "job_class" => "TestWorkerJob", "args" => [] })
    end

    it "maps a read timeout (request already sent) to WorkerOutcomeUnknownError" do
      allow(http_double).to receive(:request).and_raise(Net::ReadTimeout)
      expect { call_it }.to raise_error(WorkerJobService::WorkerOutcomeUnknownError)
    end

    it "maps a failed connection open (request never sent) to WorkerNotSentError" do
      allow(http_double).to receive(:request).and_raise(Net::OpenTimeout)
      expect { call_it }.to raise_error(WorkerJobService::WorkerNotSentError)
    end

    it "maps connection refused to WorkerNotSentError" do
      allow(http_double).to receive(:request).and_raise(Errno::ECONNREFUSED)
      expect { call_it }.to raise_error(WorkerJobService::WorkerNotSentError)
    end

    it "maps a mid-flight connection reset to WorkerOutcomeUnknownError" do
      allow(http_double).to receive(:request).and_raise(Errno::ECONNRESET)
      expect { call_it }.to raise_error(WorkerJobService::WorkerOutcomeUnknownError)
    end

    it "maps a dropped connection (EOFError) to WorkerOutcomeUnknownError" do
      allow(http_double).to receive(:request).and_raise(EOFError)
      expect { call_it }.to raise_error(WorkerJobService::WorkerOutcomeUnknownError)
    end

    it "maps an SSL error mid-request to WorkerOutcomeUnknownError" do
      allow(http_double).to receive(:request).and_raise(OpenSSL::SSL::SSLError)
      expect { call_it }.to raise_error(WorkerJobService::WorkerOutcomeUnknownError)
    end

    it "maps a generic Timeout::Error to WorkerOutcomeUnknownError" do
      allow(http_double).to receive(:request).and_raise(Timeout::Error)
      expect { call_it }.to raise_error(WorkerJobService::WorkerOutcomeUnknownError)
    end

    it "maps SocketError to WorkerNotSentError" do
      allow(http_double).to receive(:request).and_raise(SocketError)
      expect { call_it }.to raise_error(WorkerJobService::WorkerNotSentError)
    end

    it "maps EHOSTUNREACH to WorkerNotSentError" do
      allow(http_double).to receive(:request).and_raise(Errno::EHOSTUNREACH)
      expect { call_it }.to raise_error(WorkerJobService::WorkerNotSentError)
    end

    it "maps a bad worker_url (URI construction fails) to WorkerNotSentError" do
      allow(described_class).to receive(:worker_api_base).and_return("http://bad host with spaces")
      expect { call_it }.to raise_error(WorkerJobService::WorkerNotSentError)
    end

    it "maps a 4xx response to WorkerRejectedError" do
      stub_response(code: 422, body: '{"error":"nope"}')
      expect { call_it }.to raise_error(WorkerJobService::WorkerRejectedError)
    end

    it "maps a 5xx response to WorkerOutcomeUnknownError (may have already been processed)" do
      stub_response(code: 502, body: '{"error":"bad gateway"}')
      expect { call_it }.to raise_error(WorkerJobService::WorkerOutcomeUnknownError)
    end

    it "maps an unexpected status code to WorkerOutcomeUnknownError" do
      stub_response(code: 100, body: nil)
      expect { call_it }.to raise_error(WorkerJobService::WorkerOutcomeUnknownError)
    end

    it "maps a 2xx with an unparseable body to WorkerResponseUnparseableError (job IS enqueued)" do
      stub_response(code: 200, body: "not json")
      expect { call_it }.to raise_error(WorkerJobService::WorkerResponseUnparseableError)
    end

    it "returns the parsed body on a clean 2xx" do
      stub_response(code: 200, body: '{"job_id":"abc"}')
      expect(call_it).to eq({ "job_id" => "abc" })
    end

    it "every mapped error is still a WorkerServiceError (existing rescue sites keep working)" do
      allow(http_double).to receive(:request).and_raise(Net::OpenTimeout)
      expect { call_it }.to raise_error(WorkerJobService::WorkerServiceError)
    end

    # Exercises the REAL .system_worker_jwt (not stubbed, unlike the outer
    # `before` block) so the "no active system worker" raise itself is
    # proven to map to WorkerNotSentError, not just asserted by reading the
    # source.
    context "when there is no active system worker" do
      before do
        # Undo the outer before's stub so .system_worker_jwt runs for real.
        allow(described_class).to receive(:system_worker_jwt).and_call_original
        Thread.current[:_system_worker_jwt] = nil
        allow(Worker).to receive(:system_worker).and_return(nil)
      end

      it "maps the resulting failure to WorkerNotSentError" do
        expect { call_it }.to raise_error(WorkerJobService::WorkerNotSentError)
      end
    end
  end
end
