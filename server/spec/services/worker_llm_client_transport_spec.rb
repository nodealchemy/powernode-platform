# frozen_string_literal: true

require "rails_helper"

RSpec.describe WorkerLlmClient, "transport error mapping" do
  subject(:client) { described_class.new(skip_budget_tracking: true) }

  let(:worker_url) { Rails.application.config.worker_url.chomp("/") }
  let(:path) { "/api/v1/llm/complete" }

  before do
    allow(WorkerJobService).to receive(:system_worker_jwt).and_return("test-jwt")
    allow(Rails.logger).to receive(:error)
  end

  it "returns the parsed worker payload on success" do
    stub_request(:post, "#{worker_url}#{path}")
      .to_return(status: 200, body: { "data" => { "content" => "hi", "finish_reason" => "stop" } }.to_json)

    response = client.complete(messages: [{ role: "user", content: "hey" }], model: "test-model")

    expect(response.content).to eq("hi")
    expect(response.finish_reason).to eq("stop")
  end

  it "raises WorkerLlmError with the worker's error message on non-2xx" do
    stub_request(:post, "#{worker_url}#{path}")
      .to_return(status: 422, body: { "error" => "no credential" }.to_json)

    expect { client.complete(messages: [], model: "test-model") }
      .to raise_error(described_class::WorkerLlmError, "no credential")
  end

  it "falls back to an HTTP-status message when the error body is not JSON" do
    stub_request(:post, "#{worker_url}#{path}").to_return(status: 500, body: "boom")

    expect { client.complete(messages: [], model: "test-model") }
      .to raise_error(described_class::WorkerLlmError, /Worker LLM call failed \(HTTP 500\)/)
  end

  it "maps timeouts to a WorkerLlmError timeout message" do
    stub_request(:post, "#{worker_url}#{path}").to_timeout

    expect { client.complete(messages: [], model: "test-model") }
      .to raise_error(described_class::WorkerLlmError, /Worker LLM timeout/)
  end

  it "maps connection failures to a worker-unavailable WorkerLlmError" do
    stub_request(:post, "#{worker_url}#{path}").to_raise(Errno::ECONNREFUSED)

    expect { client.complete(messages: [], model: "test-model") }
      .to raise_error(described_class::WorkerLlmError, /Worker unavailable/)
  end

  it "maps an invalid 2xx JSON body to an invalid-response WorkerLlmError" do
    stub_request(:post, "#{worker_url}#{path}").to_return(status: 200, body: "not json")

    expect { client.complete(messages: [], model: "test-model") }
      .to raise_error(described_class::WorkerLlmError, "Invalid response from worker")
  end
end
