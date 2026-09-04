# frozen_string_literal: true

require "rails_helper"

# HIER-P2I (proposal §5 ruling 8) — acceptance 1: every door that hands an
# agent principal to EXECUTION resolves the account's clone, not the global
# canonical. `Ai::Agent.for_account` deliberately includes the canonicals so a
# consumer can SEE one, which is why each executing door has to map; the reads
# (show, Ai::Agent.resolve_concierge_for, platform.route_task) are left alone.
RSpec.describe "canonical principals at the execution doors (HIER-P2I)", type: :request do
  include PermissionTestHelpers

  let(:seeding_account) { create(:account, name: "Powernode Admin") }
  let(:account) { create(:account) }
  let!(:user) do
    user_with_permissions("ai.agents.read", "ai.agents.create", "ai.agents.update", "ai.agents.execute",
                          "ai.conversations.read", "ai.conversations.create", "ai.conversations.update",
                          account: account)
  end
  let(:provider) { create(:ai_provider, provider_type: "openai") }
  let!(:credential) { create(:ai_provider_credential, provider: provider, account: account, is_active: true) }
  let(:canonical) do
    create(:ai_agent, :global, owner_account: seeding_account, name: "Platform Developer",
                              slug: "platform-developer", source_key: "platform-developer",
                              agent_type: "code_assistant", is_system: true, status: "active",
                              provider: provider)
  end
  let(:headers) { auth_headers_for(user).merge("CONTENT_TYPE" => "application/json") }

  def clone_of(canonical) = Ai::Agent.find_by(cloned_from_id: canonical.id, account_id: account.id)

  describe "POST /api/v1/ai/agents/:agent_id/conversations" do
    it "attaches the conversation to the account's clone, not the canonical" do
      post "/api/v1/ai/agents/#{canonical.id}/conversations",
           params: { title: "HIER-P2I" }.to_json, headers: headers

      expect(response).to have_http_status(:created), response.body
      clone = clone_of(canonical)
      expect(clone).to be_present
      expect(Ai::Conversation.find_by(title: "HIER-P2I").ai_agent_id).to eq(clone.id)
    end

    it "leaves an account-owned agent alone" do
      own = create(:ai_agent, account: account, creator: user, provider: provider, status: "active")

      post "/api/v1/ai/agents/#{own.id}/conversations",
           params: { title: "own" }.to_json, headers: headers

      expect(response).to have_http_status(:created), response.body
      expect(Ai::Conversation.find_by(title: "own").ai_agent_id).to eq(own.id)
    end
  end

  describe "Ai::WorkspaceService#add_agents_to_team" do
    # A workspace member IS executed (Ai::TeamStrategies::BaseStrategy builds an
    # Ai::McpAgentExecutor for it), so a canonical must not join as a principal.
    it "adds the account's clone when a global canonical id is passed" do
      canonical.update!(status: "active")
      create(:ai_agent, account: account, provider: provider, is_concierge: true, status: "active",
                        name: "Powernode Assistant", creator: user)
      service = Ai::WorkspaceService.new(account: account, user: user)

      result = service.create_workspace(name: "ws", agent_ids: [ canonical.id ])

      clone = clone_of(canonical)
      expect(clone).to be_present
      member_ids = result[:team].members.pluck(:ai_agent_id)
      expect(member_ids).to include(clone.id)
      expect(member_ids).not_to include(canonical.id)
    end
  end

  describe "Ai::Tools::ConversationTool create_workspace(include_concierge:)" do
    it "seats the account's concierge clone rather than the global concierge" do
      global = create(:ai_agent, :global, owner_account: seeding_account, is_concierge: true,
                                          status: "active", name: "Powernode Assistant",
                                          slug: "powernode-assistant", source_key: "powernode-assistant",
                                          is_system: true, provider: provider)

      result = Ai::Tools::ConversationTool.new(account: account, user: user)
                                          .execute(params: { action: "create_workspace", name: "ws",
                                                             include_concierge: true })

      expect(result[:success]).to be(true), result.inspect
      clone = clone_of(global)
      expect(clone).to be_present
      expect(result[:workspace][:members].map { |m| m[:agent_id] }).to include(clone.id)
      expect(result[:workspace][:members].map { |m| m[:agent_id] }).not_to include(global.id)
    end
  end
end
