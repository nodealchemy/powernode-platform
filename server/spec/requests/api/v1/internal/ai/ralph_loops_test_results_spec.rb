# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Internal::Ai::RalphLoops test_results callback", type: :request do
  include_context "internal api auth"

  let(:ralph_loop) { create(:ai_ralph_loop, account: internal_account, status: "running") }
  let(:task) { create(:ai_ralph_task, ralph_loop: ralph_loop, status: "in_progress") }
  let(:iteration) { create(:ai_ralph_iteration, :completed, ralph_loop: ralph_loop, ralph_task: task) }

  def path(loop_id = ralph_loop.id, iter_id = iteration.id)
    "/api/v1/internal/ai/ralph_loops/#{loop_id}/iterations/#{iter_id}/test_results"
  end

  it "passes the task when the suite passed" do
    post path, params: { test_result: { framework: "rspec", command: "bundle exec rspec",
                                         exit_code: 0, output: "12 examples, 0 failures" } },
         headers: service_headers, as: :json

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body).dig("data", "passed")).to be true
    expect(task.reload.status).to eq("passed")
    expect(iteration.reload.checks_passed).to be true
    expect(iteration.check_results.dig("test_result", "failed_count")).to eq(0)
    expect(iteration.check_results["awaiting_test_result"]).to be false
  end

  it "leaves the task for retry when the suite failed (clean exit, parsed failures)" do
    post path, params: { test_result: { framework: "rspec", exit_code: 0, output: "12 examples, 3 failures" } },
         headers: service_headers, as: :json

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body).dig("data", "passed")).to be false
    expect(task.reload.status).to eq("in_progress")
    expect(iteration.reload.checks_passed).to be false
    expect(iteration.check_results.dig("test_result", "failed_count")).to eq(3)
  end

  it "treats a worker-side error as a failure and surfaces it" do
    post path, params: { test_result: { framework: "rspec", exit_code: 1, output: "", error: "clone denied" } },
         headers: service_headers, as: :json

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body).dig("data", "passed")).to be false
    expect(iteration.reload.check_results.dig("test_result", "error")).to match(/clone denied/)
  end

  it "scrubs secrets from worker-posted output and error before persisting (G15)" do
    post path, params: { test_result: { framework: "rspec", exit_code: 1,
                                        output: "boom\napi_key=sk-ABCDEF1234567890ABCDEF\n1 example, 1 failure",
                                        error: "GITHUB_TOKEN=ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ012345" } },
         headers: service_headers, as: :json

    expect(response).to have_http_status(:ok)
    stored = iteration.reload.check_results["test_result"]
    expect(stored["output"]).to include("[REDACTED]")
    expect(stored["output"]).not_to include("sk-ABCDEF1234567890ABCDEF")
    expect(stored["error"]).not_to include("ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ012345")
  end

  it "404s for an unknown iteration" do
    post path(ralph_loop.id, "00000000-0000-0000-0000-000000000000"),
         params: { test_result: { framework: "rspec", exit_code: 0, output: "" } },
         headers: service_headers, as: :json

    expect(response).to have_http_status(:not_found)
  end
end
