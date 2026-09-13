# frozen_string_literal: true

require "rails_helper"

# IMP-01a06b9a asked whether a GLOBAL canonical agent with attached external MCP
# tools escapes the HIER-P2I refusal. The branch it names is real:
# AgentToolBridgeService#dispatch_tool_call returns dispatch_external_mcp_tool
# BEFORE reaching McpPlatformToolRegistrar, so BaseTool#canonical_principal? —
# the "a template never executes" refusal — is never consulted on it. Its own two
# gates (external_mcp_available?, McpTool#can_execute?) ask only about the
# CREATOR's permissions; neither asks what kind of agent is acting.
#
# It is nonetheless unreachable, and not by anything in that file. The masking
# line is in Ai::Agent::McpServerIntegration#mcp_servers:
#
#     return McpServer.none if account.nil? || mcp_server_ids.empty?
#
# A global canonical has account_id NULL, so it resolves no servers, advertises
# no external tools, and the dispatch fork's `external_tool_index.key?(name)`
# is false for every name — it always falls through to the platform registrar,
# where the canonical refusal does apply.
#
# PINNED HERE BECAUSE THE SAFETY IS ACCIDENTAL. Nothing on the dispatch branch
# says "not a canonical"; the guarantee rests on one short-circuit in an
# unrelated concern, written for a different reason ("a global agent has no
# external servers"). Widening that line — to let global agents carry servers,
# say — would make this offer's scenario real with no failing test. These
# examples make that coupling visible at both ends.
RSpec.describe "a global canonical cannot reach the external MCP dispatch branch" do
  let(:account) { create(:account) }
  let(:creator) { create(:user, account: account, permissions: %w[mcp.tools.execute]) }

  let(:server) do
    McpServer.create!(account: account, name: "probe-srv", status: "connected",
                      connection_type: "stdio", command: "/bin/true")
  end

  let!(:tool) do
    McpTool.create!(mcp_server: server, name: "probe_tool", enabled: true,
                    input_schema: { "type" => "object" })
  end

  # Attached the only way a canonical could be: by metadata. mcp_server_ids is a
  # JSONB read, so it accepts an id whether or not the row is reachable.
  def attach!(agent)
    agent.mcp_server_ids = [ server.id ]
    agent.save!
    agent
  end

  let(:canonical) do
    agent = Ai::Agent.new(name: "Canonical Probe", agent_type: "assistant")
    agent.account_id = nil
    agent.creator = creator
    agent.is_system = true
    agent.source_key = "canonical_probe"
    agent.save!
    attach!(agent)
  end

  let(:clone) do
    attach!(create(:ai_agent, account: account, agent_type: "assistant", creator: creator))
  end

  def index_for(agent, acct)
    Ai::AgentToolBridgeService.new(agent: agent, account: acct).send(:external_tool_index)
  end

  it "is a global canonical, so the premise holds" do
    expect(canonical.global?).to be(true)
    expect(canonical.account_id).to be_nil
    expect(canonical.mcp_server_ids).to eq([ server.id ])
  end

  it "resolves no attached server despite the metadata naming one" do
    expect(canonical.mcp_servers.count).to eq(0)
    expect(canonical.available_mcp_tools).to be_empty
  end

  it "advertises no external tool, so the dispatch fork cannot be taken" do
    expect(index_for(canonical, canonical.account)).to be_empty
  end

  # THE NON-VACUITY HALF. Without it, a fixture that simply failed to build a
  # reachable tool would satisfy every example above. The identical attachment
  # on an account-scoped agent must produce a real entry.
  it "does produce an entry for an account-scoped agent with the same attachment" do
    expect(index_for(clone, account).keys).to eq([ "mcp__probe_srv__probe_tool" ])
  end

  # The line the guarantee actually rests on, asserted where a reader of the
  # bridge would never think to look.
  it "rests on McpServerIntegration#mcp_servers short-circuiting on a nil account" do
    expect(Ai::Agent::McpServerIntegration.instance_method(:mcp_servers).source_location).to be_present
    expect(canonical.mcp_server_ids).to be_present, "the short-circuit must be the account check, not an empty id list"
    expect(canonical.mcp_servers).to be_empty
  end
end
