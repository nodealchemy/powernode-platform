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
    # Default: not suspended. The kill-switch arm below flips it.
    allow(job).to receive(:bail_if_ai_suspended!).and_return(false)
  end

  # The kill switch reaches the judge: evaluating spends an LLM call. The server
  # refuses too, but this stops the round trip. Both arms — the default above is
  # the other one, and every example that reaches the server proves it.
  it "bails before calling the server while the account's AI is suspended" do
    allow(job).to receive(:bail_if_ai_suspended!).with(account_id).and_return(true)

    # No :post_no_retry stub exists, so a call would raise.
    expect(job.execute(args)).to eq(status: "not_measured", reason: "AiSuspended")
  end

  # Sidekiq serialises args to JSON, so however the server wrote the payload it
  # arrives here with STRING keys. Every fixture below is string-keyed for that
  # reason, and the response fixtures mirror the server's real render_success
  # envelope ("data" => ...).
  def args(overrides = {})
    { "account_id" => account_id, "execution_id" => execution_id }.merge(overrides)
  end

  it "posts the ids and reports the evaluated arm" do
    allow(api_client).to receive(:post_no_retry)
      .with("/api/v1/internal/ai/evaluations/run",
            { account_id: account_id, execution_id: execution_id, task_id: task_id },
            timeout: described_class::JUDGE_TIMEOUT)
      .and_return("data" => { "status" => "evaluated", "evaluation_id" => "eval-9" })

    expect(job.execute(args("task_id" => task_id)))
      .to eq(status: "evaluated", reason: nil, evaluation_id: "eval-9")
  end

  it "omits task_id entirely when the completion carries none" do
    # Not `task_id: nil` — the server reads params[:task_id].presence, and a
    # nil in the body would be indistinguishable from an absent key only by
    # luck. The exact-args stub is the assertion.
    allow(api_client).to receive(:post_no_retry)
      .with("/api/v1/internal/ai/evaluations/run",
            { account_id: account_id, execution_id: execution_id },
            timeout: described_class::JUDGE_TIMEOUT)
      .and_return("data" => { "status" => "evaluated", "evaluation_id" => "eval-9" })

    expect(job.execute(args)[:status]).to eq("evaluated")
  end

  it "passes the server's not_measured answer straight through" do
    allow(api_client).to receive(:post_no_retry)
      .and_return("data" => { "status" => "not_measured", "reason" => "EvaluationDisabled" })

    expect(job.execute(args)).to eq(status: "not_measured", reason: "EvaluationDisabled",
                                    evaluation_id: nil)
  end

  it "refuses to call the server with a missing execution id" do
    # No :post_no_retry stub exists, so any call would raise — the returned reason is
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
    allow(api_client).to receive(:post_no_retry)
      .with("/api/v1/internal/ai/evaluations/run",
            { account_id: account_id, execution_id: execution_id },
            timeout: described_class::JUDGE_TIMEOUT)
      .and_return("data" => { "status" => "evaluated" })

    expect(job.execute(account_id: account_id, execution_id: execution_id)[:status]).to eq("evaluated")
  end

  it "lets a transport failure surface so Sidekiq retries it" do
    # Idempotency is server-side, on (execution_id, task_id), so a retry is
    # safe and swallowing the error here would lose the evaluation silently.
    allow(api_client).to receive(:post_no_retry).and_raise(Errno::ECONNRESET)

    expect { job.execute(args) }.to raise_error(Errno::ECONNRESET)
  end

  # D4 review F2 — the server 404s an execution that is missing OR belongs to
  # another account, indistinguishably. Neither can ever succeed, so a retry
  # only repeats the refusal: the 404 is terminal here, and says so.
  it "treats the server's 404 as terminal instead of retrying it" do
    allow(api_client).to receive(:post_no_retry)
      .and_raise(BackendApiClient::ApiError.new("Resource not found", 404))

    expect(job.execute(args)).to eq(status: "not_measured", reason: "ExecutionNotFound", evaluation_id: nil)
  end

  it "still lets any other server error surface, so Sidekiq retries it" do
    allow(api_client).to receive(:post_no_retry).and_raise(BackendApiClient::ApiError.new("boom", 500))

    expect { job.execute(args) }.to raise_error(BackendApiClient::ApiError)
  end

  # D5 review F-D5-2 — the judge call is PAID and synchronous. A timeout while
  # the server is still judging must not re-send the request: the first
  # request's row is not written yet, so the server's idempotency check misses
  # and a second paid call runs. Driven through the REAL client against a stub
  # at the HTTP layer, so what is counted is POSTs that actually left.
  describe "the paid judge POST, at the HTTP layer" do
    let(:client) { BackendApiClient.new }
    let(:url) { "#{test_config[:backend_api_url]}/api/v1/internal/ai/evaluations/run" }
    let(:sent_body) { { "account_id" => account_id, "execution_id" => execution_id } }
    let(:evaluated) do
      { status: 200, headers: { "Content-Type" => "application/json" },
        body: { "success" => true, "data" => { "status" => "evaluated", "evaluation_id" => "eval-9" } }.to_json }
    end

    before { allow(job).to receive(:api_client).and_return(client) }

    it "sends the judge request ONCE when it times out, and surfaces the timeout" do
      stub_request(:post, url).to_raise(Net::ReadTimeout).then.to_return(evaluated)

      outcome = begin
        job.execute(args)
      rescue BackendApiClient::ApiError => e
        e
      end

      expect(WebMock).to have_requested(:post, url).once
      expect(outcome).to be_a(BackendApiClient::ApiError)
      expect(outcome.status).to eq(408)
    end

    it "the other arm: a judge that answers is asked once, with the ids in the body" do
      stub_request(:post, url).with(body: sent_body).to_return(evaluated)

      expect(job.execute(args)).to eq(status: "evaluated", reason: nil, evaluation_id: "eval-9")
      expect(WebMock).to have_requested(:post, url).with(body: sent_body).once
    end
  end
end
