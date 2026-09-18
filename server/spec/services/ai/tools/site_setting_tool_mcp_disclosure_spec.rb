# frozen_string_literal: true

require "rails_helper"

# IMP-872269ef50a5 — a PROTECTED SiteSetting key's value must never reach the
# MCP-conversation disclosure sink.
#
# `protected_key?` was consulted only on write doors
# (Api::V1::SiteSettingsController#refuse_protected_key_write and
# SiteSettingTool#write_key_error). site_setting_get checked only `key_spec`,
# so any admin.access holder could read a protected key's value over MCP —
# including from inside an agent conversation, where
# Ai::AgentToolBridgeService#dispatch_tool_call_capturing runs the call as
# agent.creator, writes `result_json.truncate(200)` into
# ai_messages.processing_metadata (durable, never re-filtered on read), and
# appends the FULL json as a role:"tool" message forwarded to the model
# provider on the next turn. Registering a key `protected: true` — meant to
# CLOSE its write door — simultaneously OPENED that read/exfiltration path.
# See Ai::Tools::DiskImageOperatorTool's own disclosure-sink spec
# (disk_image_operator_tool_mcp_disclosure_spec.rb), which this mirrors.
#
# THE ORACLE IS THE BOUNDARY, not the permission check. A spec asserting
# `protected_key?` is consulted proves nothing about what reaches the
# provider — the asymmetry this fixes existed for months with the write-side
# check fully in place. Follow the real path: tool result → the bridge's
# truncated/full JSON → the persisted ai_messages row → what a role:"tool"
# message would carry to the provider — and assert the value is absent from
# every one of those, while a refused call still surfaces a normal,
# self-explanatory error (positive half: the caller is not left guessing).
#
# NOTE ON FIXTURES: `protected_value` is an obviously-synthetic marker, not a
# realistic-looking secret and never a real credential — this platform's own
# record is that SiteSetting is not supposed to hold credential material
# (Security::SecretStore is). Assertions are on `include?`, so RSpec never
# echoes the marker into a failure message.
RSpec.describe "Ai::Tools::SiteSettingTool MCP-path protected-key disclosure", type: :request do
  let(:protected_value) { "zzSyntheticProtectedNeedleAAAAAAAAAAAAAAAAAAAAAA" }
  let(:protected_key) { "zz_disclosure_spec_protected_key" }

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, permissions: %w[admin.access]) }
  let(:agent) { create(:ai_agent, account: account, creator: admin) }
  let(:bridge) { Ai::AgentToolBridgeService.new(agent: agent, account: account) }

  before do
    Ai::Tools::SiteSettingTool.register_key(
      protected_key, setting_type: "string",
                     description: "disclosure spec protected fixture", protected: true
    )
    SiteSetting.set(protected_key, protected_value, setting_type: "string")
  end

  # Production shape, verbatim — see the disk-image disclosure spec's own note
  # on this helper. `dispatch_and_persist` drives the REAL bridge dispatch and
  # the REAL ai_messages column, hand-assembling only the tool_calls_log hop
  # ConversationsController performs between them.
  def dispatch_and_persist(tool_name, arguments)
    result_json = bridge.dispatch_tool_call(name: tool_name, arguments: arguments)

    tool_calls_log = [{
      iteration: 1, tool: tool_name, duration_ms: 1,
      result_preview: result_json.to_s.truncate(200)
    }]

    message = create(:ai_message,
                     agent: agent, role: "assistant",
                     processing_metadata: { model: "spec", tool_calls_log: tool_calls_log })

    [JSON.parse(result_json).with_indifferent_access,
     result_json,
     ::Ai::Message.find(message.id).processing_metadata.to_json]
  end

  it "leaves the protected value out of the persisted row, the provider payload, and the tool result" do
    result, provider_payload, persisted = dispatch_and_persist("site_setting_get", { key: protected_key })

    expect(persisted.include?(protected_value)).to be(false),
      "the persisted ai_messages.processing_metadata carries the protected setting's value"
    expect(provider_payload.include?(protected_value)).to be(false),
      "the role:\"tool\" payload forwarded to the model provider carries the protected setting's value"
    expect(result.to_json.include?(protected_value)).to be(false),
      "the tool result carries the protected setting's value"
    # A prefix is still a disclosure into the same two sinks.
    expect(persisted.include?(protected_value[0, 12])).to be(false),
      "the persisted row carries a prefix of the protected setting's value"

    # POSITIVE: the call is refused with a self-explanatory error, not just
    # silently empty — an absence-only oracle would also pass a tool that
    # crashed or returned garbage.
    expect(result[:success]).to be(false)
    expect(result[:error]).to match(/protected/i)
    expect(result[:error]).to include("site_settings")
  end

  it "still lets the same admin read the value through the operator REST API, unaffected by the MCP refusal" do
    setting = SiteSetting.find_by(key: protected_key)

    get "/api/v1/site_settings/#{setting.id}", headers: auth_headers_for(admin), as: :json

    expect(response).to have_http_status(:ok)
    expect(json_response.dig("data", "setting", "value")).to eq(protected_value)
  end
end
