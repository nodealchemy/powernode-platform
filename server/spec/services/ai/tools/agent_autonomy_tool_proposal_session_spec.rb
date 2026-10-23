# frozen_string_literal: true

require "rails_helper"

# A proposal records the MCP session it was filed through, from the tool's OWN
# owner-resolved session (set by the MCP controller), never from params.
RSpec.describe Ai::Tools::AgentAutonomyTool, "proposal origin session" do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:agent) { create(:ai_agent, account: account) }
  let(:session) { McpSession.create!(user: user, account: account) }
  let(:tool) { described_class.new(account: account, user: user, agent: agent) }

  before { allow_any_instance_of(Ai::AgentOutreachService).to receive(:notify_proposal).and_return(true) }

  def create_params(**extra)
    { action: "create_proposal", proposal_type: "feature", title: "T", description: "D" }.merge(extra).with_indifferent_access
  end

  it "records the tool's own session" do
    tool.mcp_session_id = session.id
    result = tool.execute(params: create_params)

    expect(result[:success]).to be(true), result.inspect
    expect(Ai::AgentProposal.order(:created_at, :id).last.origin_mcp_session_id).to eq(session.id)
  end

  it "8. a session id supplied in params is refused as an unknown parameter and files nothing" do
    forged = SecureRandom.uuid
    tool.mcp_session_id = session.id
    result = tool.execute(params: create_params(origin_mcp_session_id: forged, mcp_session_id: forged))

    expect(result[:success]).to be false
    expect(result[:error]).to match(/Unrecognized parameter/)
    expect(Ai::AgentProposal.count).to eq(0)
  end

  it "a proposal filed with no MCP session records none" do
    tool.execute(params: create_params)
    expect(Ai::AgentProposal.order(:created_at, :id).last.origin_mcp_session_id).to be_nil
  end
end
