# frozen_string_literal: true

require "rails_helper"

# D4 — worker side of the LLM judge. Event-driven: the server enqueues one of
# these per completion, so there is no cron entry and no sweep. Every gate is
# server-side, so this job's whole contract is "pass the ids through, and do
# not pretend a no-op was a success".
RSpec.describe AgentEvaluationJob, type: :job do
  let(:api_client) { instance_double(BackendApiClient) }
  let(:job) { described_class.new }
  let(:account_id) { "acc-1" }
  let(:execution_id) { "exec-1" }
  let(:task_id) { "task-1" }

  before do
    mock_powernode_worker_config
    allow(job).to receive(:api_client).and_return(api_client)
    allow(job).to receive(:log_info)
    allow(job).to receive(:log_warn)
  end

  # Sidekiq serialises args to JSON, so however the server wrote the payload it
  # arrives here with STRING keys. Every fixture below is string-keyed for that
  # reason, and the response fixtures mirror the server's real render_success
  # envelope ("data" => ...).
  def args(overrides = {})
    { "account_id" => account_id, "execution_id" => execution_id }.merge(overrides)
  end

  it "posts the ids and reports the evaluated arm" do
    allow(api_client).to receive(:post)
      .with("/api/v1/internal/ai/evaluations/run",
            { account_id: account_id, execution_id: execution_id, task_id: task_id })
      .and_return("data" => { "status" => "evaluated", "evaluation_id" => "eval-9" })

    expect(job.execute(args("task_id" => task_id)))
      .to eq(status: "evaluated", reason: nil, evaluation_id: "eval-9")
  end

  it "omits task_id entirely when the completion carries none" do
    # Not `task_id: nil` — the server reads params[:task_id].presence, and a
    # nil in the body would be indistinguishable from an absent key only by
    # luck. The exact-args stub is the assertion.
    allow(api_client).to receive(:post)
      .with("/api/v1/internal/ai/evaluations/run",
            { account_id: account_id, execution_id: execution_id })
      .and_return("data" => { "status" => "evaluated", "evaluation_id" => "eval-9" })

    expect(job.execute(args)[:status]).to eq("evaluated")
  end

  it "passes the server's not_measured answer straight through" do
    allow(api_client).to receive(:post)
      .and_return("data" => { "status" => "not_measured", "reason" => "EvaluationDisabled" })

    expect(job.execute(args)).to eq(status: "not_measured", reason: "EvaluationDisabled",
                                    evaluation_id: nil)
  end

  it "refuses to call the server with a missing execution id" do
    # No :post stub exists, so any call would raise — the returned reason is
    # what proves it returned instead of posting a payload of nils, which the
    # server would answer with a cheerful not_measured that looks like success.
    expect(job.execute("account_id" => account_id))
      .to eq(status: "not_measured", reason: "MissingArguments")
  end

  it "refuses to call the server with a missing account id" do
    expect(job.execute("execution_id" => execution_id))
      .to eq(status: "not_measured", reason: "MissingArguments")
  end

  it "reads SYMBOL-keyed args too, since a direct in-process call is not JSON" do
    allow(api_client).to receive(:post)
      .with("/api/v1/internal/ai/evaluations/run",
            { account_id: account_id, execution_id: execution_id })
      .and_return("data" => { "status" => "evaluated" })

    expect(job.execute(account_id: account_id, execution_id: execution_id)[:status]).to eq("evaluated")
  end

  it "lets a transport failure surface so Sidekiq retries it" do
    # Idempotency is server-side, on (execution_id, task_id), so a retry is
    # safe and swallowing the error here would lose the evaluation silently.
    allow(api_client).to receive(:post).and_raise(Errno::ECONNRESET)

    expect { job.execute(args) }.to raise_error(Errno::ECONNRESET)
  end
end
