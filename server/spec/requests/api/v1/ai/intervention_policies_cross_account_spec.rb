# frozen_string_literal: true

require "rails_helper"

# An intervention-policy row may only reference its OWN account's agent (or a
# global canonical one) and its own account's approval chain.
#
# Ai::InterventionPolicy's belongs_to :agent / :approval_chain carry no account
# check, so a writer that assigns the raw ids lets account A point a row at
# account B's chain: the grouped view then shows B's chain and agent names to A,
# and the autonomy gate routes A's actions to B's approvers. Every door that
# writes these rows resolves the ids through the caller's account instead, and
# an id it cannot resolve (another account's, or one that does not exist) is
# refused with nothing written — never a 500 that aborts a batch half-written.
RSpec.describe "Intervention-policy writes referencing another account", type: :request do
  let(:account)       { create(:account) }
  let(:other_account) { create(:account) }
  let(:operator)      { user_with_permissions("ai.intervention_policies.manage", account: account) }

  let(:own_agent)     { create(:ai_agent, account: account) }
  let(:foreign_agent) { create(:ai_agent, account: other_account) }
  let(:own_chain)     { create(:ai_approval_chain, account: account) }
  let(:foreign_chain) { create(:ai_approval_chain, account: other_account) }
  let(:missing_id)    { SecureRandom.uuid }

  def headers
    auth_headers_for(operator).merge("Content-Type" => "application/json")
  end

  def errors
    Array(json_response.dig("details", "errors")).join(" ")
  end

  describe "PATCH /api/v1/ai/intervention_policies/bulk" do
    def bulk(*updates)
      patch "/api/v1/ai/intervention_policies/bulk", params: { updates: updates }.to_json, headers: headers
    end

    it "refuses another account's agent, writing no row for it" do
      bulk({ action_category: "dev.task_requeue", policy: "block", scope: "agent", agent_id: foreign_agent.id })

      expect(response).to have_http_status(:unprocessable_content)
      expect(errors).to include("unknown agent")
      expect(Ai::InterventionPolicy.where(ai_agent_id: foreign_agent.id)).to be_empty
    end

    it "refuses another account's approval chain, leaving the row's chain as it was" do
      row = Ai::InterventionPolicy.create!(account: account, action_category: "dev.task_requeue", scope: "global",
                                           policy: "require_approval", priority: 5, approval_chain_id: own_chain.id)

      bulk({ action_category: "dev.task_requeue", policy: "block", scope: "global", approval_chain_id: foreign_chain.id })

      expect(response).to have_http_status(:unprocessable_content)
      expect(errors).to include("unknown approval chain")
      expect(row.reload.approval_chain_id).to eq(own_chain.id)
      expect(row.policy).to eq("require_approval")
    end

    # A nonexistent id used to reach the database as a foreign key: an
    # unrescued InvalidForeignKey 500 that aborted the batch after earlier
    # entries were already written, with no report of which.
    it "refuses a nonexistent agent or chain per entry, keeping the batch and its report intact" do
      bulk({ action_category: "dev.task_requeue", policy: "block", scope: "global" },
           { action_category: "dev.multi_file_change", policy: "block", scope: "agent", agent_id: missing_id },
           { action_category: "ralph.repository_write", policy: "block", scope: "global", approval_chain_id: missing_id })

      expect(response).to have_http_status(:unprocessable_content)
      expect(json_response.dig("details", "changed")).to eq(1)
      expect(errors).to include("[1] unknown agent", "[2] unknown approval chain")
      expect(Ai::InterventionPolicy.where(account: account).pluck(:action_category)).to eq([ "dev.task_requeue" ])
    end

    # Positive controls: the account's own agent and chain, and a global
    # canonical agent (account_id nil — the system agents' shape), still work.
    it "accepts the account's own agent and chain, and a global agent" do
      global_agent = create(:ai_agent, account: account).tap { |a| a.update_column(:account_id, nil) }

      bulk({ action_category: "dev.task_requeue", policy: "block", scope: "agent", agent_id: own_agent.id,
             approval_chain_id: own_chain.id },
           { action_category: "dev.multi_file_change", policy: "block", scope: "agent", agent_id: global_agent.id })

      expect(response).to have_http_status(:ok)
      expect(Ai::InterventionPolicy.find_by!(account: account, ai_agent_id: own_agent.id).approval_chain_id)
        .to eq(own_chain.id)
      expect(Ai::InterventionPolicy.where(account: account, ai_agent_id: global_agent.id)).to exist
    end
  end

  describe "core CRUD" do
    let(:body) { { scope: "agent", action_category: "dev.task_requeue", policy: "block", priority: 10 } }

    it "refuses creating a row for another account's agent" do
      post "/api/v1/ai/intervention_policies", params: body.merge(ai_agent_id: foreign_agent.id).to_json,
                                               headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(json_response["error"]).to include("unknown agent")
      expect(Ai::InterventionPolicy.where(ai_agent_id: foreign_agent.id)).to be_empty
    end

    it "refuses re-pointing a row at another account's agent, or at one that does not exist" do
      row = Ai::InterventionPolicy.create!(account: account, action_category: "dev.task_requeue", scope: "agent",
                                           ai_agent_id: own_agent.id, policy: "require_approval", priority: 10)

      [ foreign_agent.id, missing_id ].each do |agent_id|
        patch "/api/v1/ai/intervention_policies/#{row.id}", params: { ai_agent_id: agent_id }.to_json, headers: headers

        expect(response).to have_http_status(:unprocessable_content)
        expect(row.reload.ai_agent_id).to eq(own_agent.id)
      end
    end

    # user_id names whose row it is, and the serializer ships that user's email:
    # another account's user would leak their address to this account.
    it "refuses creating or re-pointing a row at another account's user, or one that does not exist" do
      foreign_user = create(:user, account: other_account)

      post "/api/v1/ai/intervention_policies",
           params: { scope: "global", action_category: "dev.task_requeue", policy: "block", user_id: foreign_user.id }.to_json,
           headers: headers
      expect(response).to have_http_status(:unprocessable_content)
      expect(json_response["error"]).to include("unknown user")
      expect(Ai::InterventionPolicy.where(user_id: foreign_user.id)).to be_empty

      row = Ai::InterventionPolicy.create!(account: account, action_category: "dev.task_requeue", scope: "global",
                                           user_id: operator.id, policy: "require_approval", priority: 5)
      [ foreign_user.id, missing_id ].each do |user_id|
        patch "/api/v1/ai/intervention_policies/#{row.id}", params: { user_id: user_id }.to_json, headers: headers

        expect(response).to have_http_status(:unprocessable_content)
        expect(row.reload.user_id).to eq(operator.id)
      end
      expect(response.body).not_to include(foreign_user.email)
    end

    it "still accepts the account's own user" do
      post "/api/v1/ai/intervention_policies",
           params: { scope: "global", action_category: "dev.task_requeue", policy: "block", user_id: operator.id }.to_json,
           headers: headers

      expect(response).to have_http_status(:created)
    end

    it "still creates a row for the account's own agent" do
      post "/api/v1/ai/intervention_policies", params: body.merge(ai_agent_id: own_agent.id).to_json, headers: headers

      expect(response).to have_http_status(:created)
    end
  end

  # The MCP door (platform.create_intervention_policy) parks for a person and,
  # once approved, runs this writer with the params as sent — so it must resolve
  # the ids too.
  describe "the MCP tool's create writer" do
    let(:tool) { ::Ai::Tools::AgentAutonomyTool.new(account: account, user: operator) }
    let(:params) { { scope: "agent", action_category: "dev.task_requeue", policy: "block" } }

    def create_via_tool(extra)
      tool.send(:create_intervention_policy, params.merge(extra))
    end

    it "refuses another account's agent or approval chain, writing nothing" do
      expect(create_via_tool(ai_agent_id: foreign_agent.id)).to include(success: false, error: /unknown agent/)
      expect(create_via_tool(ai_agent_id: own_agent.id, approval_chain_id: foreign_chain.id))
        .to include(success: false, error: /unknown approval chain/)
      expect(create_via_tool(ai_agent_id: missing_id)).to include(success: false)

      expect(account.ai_intervention_policies).to be_empty
    end

    it "still creates a row for the account's own agent and chain" do
      expect(create_via_tool(ai_agent_id: own_agent.id, approval_chain_id: own_chain.id)).to include(success: true)
    end
  end
end
