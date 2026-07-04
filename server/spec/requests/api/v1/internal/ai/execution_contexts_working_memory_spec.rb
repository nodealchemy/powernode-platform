# frozen_string_literal: true

require "rails_helper"

# The execution-context build never passes a task, and the only production
# writer (Ai::McpAgentExecutor::MemoryWriteback#write_working_memory_state)
# never passes one either -- both are agent-scoped. Working memory injection
# used to hard-gate on task.present? (context_injector_service.rb:35), which
# meant it silently never fired on this path at all -- fixed in IMP-c51ef070f4ca.
# This replaces the older "does not hydrate working memory" regression lock
# (IMP-573fbbd9a2b7), which pinned that gap as if it were correct behavior;
# that fix's actual target was proactive DB->Redis hydration ahead of the
# call (never reintroduced here), not the read itself.
RSpec.describe "Internal::Ai execution_contexts injects agent-scoped working memory", type: :request do
  include_context "internal api auth"

  let(:agent) { create(:ai_agent, account: internal_account) }
  let(:path) { "/api/v1/internal/ai/execution_contexts" }

  it "surfaces working memory written without a task into additional_context" do
    working_memory = ::Ai::Memory::WorkingMemoryService.new(agent: agent, account: internal_account)
    working_memory.store_task_state({ "last_output" => "previous execution result" })

    post path, params: { agent_id: agent.id, input: "hello" }.to_json, headers: service_headers

    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body.dig("data", "execution_context", "additional_context")).to include("previous execution result")
  end

  it "does not reintroduce DB->Redis hydration ahead of the read (no load_from_database call)" do
    expect_any_instance_of(::Ai::Memory::WorkingMemoryService).not_to receive(:load_from_database)

    post path, params: { agent_id: agent.id, input: "hello" }.to_json, headers: service_headers

    expect(response).to have_http_status(:ok)
  end
end
