# frozen_string_literal: true

require "rails_helper"

# Cross-app contract: `system_prompt` must survive the server -> worker LLM proxy
# on EVERY /llm/* endpoint. Each side dropped it silently on some endpoints
# (complete_structured and execute_tool_loop on the producer; complete_with_tools,
# complete_structured and execute_tool_loop on the consumer), so the concierge's
# whole tool-path prompt and the Ai::Reasoning::* prompts never reached a model.
#
# Producer half: WorkerLlmClient puts system_prompt in the request body.
# Consumer half: statically, because scripts/validate.sh runs server/spec only and
# never worker/spec (same reasoning as worker_job_class_contract_spec.rb). The
# worker's request-level half lives in
# worker/spec/controllers/jobs_controller_llm_system_prompt_spec.rb.
RSpec.describe WorkerLlmClient, "system_prompt contract" do
  subject(:client) { described_class.new(skip_budget_tracking: true) }

  let(:worker_url) { Rails.application.config.worker_url.chomp("/") }
  let(:messages) { [ { role: "user", content: "hi" } ] }
  let(:system_prompt) { "You are the contract-test agent." }

  endpoints = {
    "complete" => ->(c, m, sp) { c.complete(messages: m, model: "test-model", system_prompt: sp) },
    "stream" => ->(c, m, sp) { c.stream(messages: m, model: "test-model", system_prompt: sp) },
    "complete_with_tools" => lambda { |c, m, sp|
      c.complete_with_tools(messages: m, tools: [], model: "test-model", system_prompt: sp)
    },
    "complete_structured" => lambda { |c, m, sp|
      c.complete_structured(messages: m, schema: { "type" => "object" }, model: "test-model", system_prompt: sp)
    },
    "execute_tool_loop" => ->(c, m, sp) { c.execute_tool_loop(messages: m, model: "test-model", system_prompt: sp) }
  }

  before do
    allow(WorkerJobService).to receive(:system_worker_jwt).and_return("test-jwt")
  end

  describe "producer: the request body carries system_prompt" do
    endpoints.each do |endpoint, call|
      it "sends system_prompt to /api/v1/llm/#{endpoint}" do
        stub = stub_request(:post, "#{worker_url}/api/v1/llm/#{endpoint}")
               .with { |req| JSON.parse(req.body)["system_prompt"] == system_prompt }
               .to_return(status: 200, body: { "data" => { "content" => "ok" } }.to_json)

        call.call(client, messages, system_prompt)

        expect(stub).to have_been_requested
      end
    end
  end

  describe "consumer: every worker /llm/* action reads system_prompt" do
    controller = Rails.root.parent.join("worker", "app", "controllers", "jobs_controller.rb")

    endpoints.each_key do |endpoint|
      it "worker JobsController#llm_#{endpoint} extracts system_prompt" do
        source = File.read(controller)
        body = source[/^  def llm_#{endpoint}\(request\)\n(.*?)^  end$/m, 1]

        expect(body).not_to be_nil, "worker JobsController has no llm_#{endpoint} action"
        expect(body).to match(/:system_prompt\b/)
      end
    end
  end
end
