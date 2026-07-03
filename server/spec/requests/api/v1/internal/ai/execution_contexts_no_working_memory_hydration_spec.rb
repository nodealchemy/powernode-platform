# frozen_string_literal: true

require "rails_helper"

# The execution-context build never passes a task, so ContextInjectorService#build_context
# never injects working memory (hard-gated on task.present?, context_injector_service.rb:35).
# Hydrating working memory into Redis ahead of that call was pure per-call waste on the
# hot agent-execution path — see IMP-573fbbd9a2b7.
RSpec.describe "Internal::Ai execution_contexts does not hydrate working memory", type: :request do
  include_context "internal api auth"

  let(:agent) { create(:ai_agent, account: internal_account) }
  let(:path) { "/api/v1/internal/ai/execution_contexts" }

  it "does not call WorkingMemoryService while building the execution context" do
    expect(::Ai::Memory::WorkingMemoryService).not_to receive(:new)

    post path, params: { agent_id: agent.id, input: "hello" }.to_json, headers: service_headers

    expect(response).to have_http_status(:ok)
  end
end
