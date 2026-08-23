# frozen_string_literal: true

require "rails_helper"

# IMP-6af3dc79efb3 — every tool listed in Ai::AgentToolBridgeService::CARD_TOOLS
# had its FULL result[:data] copied verbatim into a chat card, which
# Ai::ConciergeService writes to ai_messages.content_metadata (jsonb). That is a
# durable, untruncated, unfiltered at-rest sink, and Ai::SensitiveParams never
# sees it — the card payload is not routed through #filter.
#
# The sink under test is the COLUMN, after a reload. It is deliberately NOT the
# `result_json.to_s.truncate(200)` preview in tool_calls_log: the fixture below
# pads the declared keys so the sentinel sits past offset 200 of the serialized
# result, exactly as the real system_deploy_platform payload did
# (IMP-c0687cfb3a05, measured at offsets 245/370 of a 1146-char result). Both
# facts are asserted, so a fix aimed at the preview cannot make this pass.
RSpec.describe Ai::AgentToolBridgeService, "card payload projection (IMP-6af3dc79efb3)" do
  # Obviously fake, and named so a grep for it can never be confused with real
  # material. Nothing here is or resembles a live secret.
  #
  # `let`, not a constant: a constant assigned inside an RSpec.describe block at
  # file top level resolves against Object, so it would be global and would
  # clobber any same-named constant in another file under a defined run order.
  let(:sentinel) { "SYNTHETIC-NOT-A-REAL-SECRET-6af3dc79efb3" }

  # Deliberately innocuous key name. A denylist keyed on token/secret/key would
  # not match it — the projection must drop it because it was never DECLARED,
  # not because of what it is called.
  let(:undeclared_key) { "debug_context" }

  let(:account)  { create(:account) }
  let(:provider) { create(:ai_provider, account: account) }
  let(:user)     { create(:user, account: account) }
  let(:agent)    { create(:ai_agent, account: account, provider: provider, creator: user) }
  let(:conversation) do
    create(:ai_conversation, account: account, agent: agent, user: user, provider: provider)
  end

  subject(:bridge) { described_class.new(agent: agent, account: account) }

  let(:card_tool) { "platform_provisioning_status" }

  # Declared keys first and padded, so the sentinel lands well past the 200-char
  # preview window.
  # The model's tool-call arguments used to ride along on the card, unprojected.
  let(:tool_arguments) { { "mission_id" => "m-1", "details" => sentinel } }

  let(:tool_result) do
    {
      success: true,
      data: {
        "phase"        => "executing",
        "current_step" => 7,
        "completed"    => (1..60).to_a,
        undeclared_key => sentinel
      }
    }
  end

  let(:llm_client) { instance_double(WorkerLlmClient, provider_type: "anthropic") }

  before do
    allow(bridge).to receive(:tool_definitions_for_llm).and_return([])

    allow(Ai::Tools::McpPlatformToolRegistrar)
      .to receive(:execute_tool).and_return(tool_result)

    tool_call_response = Ai::Llm::Response.new(
      content: nil, finish_reason: "tool_use",
      tool_calls: [{ id: "call_1", name: card_tool, arguments: tool_arguments }]
    )
    final_response = Ai::Llm::Response.new(content: "Here is the status.", finish_reason: "end_turn")

    allow(llm_client).to receive(:complete_with_tools)
      .and_return(tool_call_response, final_response)
  end

  # Runs the real loop, then persists exactly as Ai::ConciergeService does
  # (concierge_service.rb: content_metadata = { cards: result[:chat_cards] }).
  def run_and_persist
    result = bridge.execute_tool_loop(
      llm_client: llm_client,
      messages: [{ role: "user", content: "status?" }],
      model: "claude-fable-5"
    )
    cards = result[:chat_cards].presence
    message = conversation.add_assistant_message(
      result[:content], content_metadata: cards ? { cards: cards } : {}
    )
    [result, message.reload]
  end

  it "does not persist an undeclared payload key to ai_messages.content_metadata" do
    _result, message = run_and_persist

    expect(message.content_metadata.to_json).not_to include(sentinel)
    expect(message.content_metadata.dig("cards", 0, "payload")).not_to have_key(undeclared_key)
  end

  it "still persists the declared keys the card renderer reads" do
    _result, message = run_and_persist

    payload = message.content_metadata.dig("cards", 0, "payload")
    expect(payload).to include("phase" => "executing", "current_step" => 7)
    expect(payload["completed"]).to eq((1..60).to_a)
    expect(message.content_metadata.dig("cards", 0, "kind")).to eq("provisioning_status")
  end

  # Second copy of the same hazard: the card used to carry the model's raw
  # tool-call arguments verbatim into the same column. ProvisioningTool#adapt
  # takes a free-form `details:` object and #capture_brief a free-form
  # `prior_brief:`, so those were caller-controlled and unprojected. No renderer
  # reads card.arguments.
  it "does not persist the model's raw tool-call arguments" do
    _result, message = run_and_persist

    expect(message.content_metadata.dig("cards", 0)).not_to have_key("arguments")
  end

  # Path proof. If the sentinel never enters the 200-char preview, then any
  # green run of the first example is attributable to the content_metadata path
  # and not to a change in the preview.
  it "proves the sink is content_metadata and not the 200-char tool_calls_log preview" do
    result, _message = run_and_persist

    preview = result[:tool_calls_log].first[:result_preview]
    expect(preview.length).to be <= 200
    expect(preview).not_to include(sentinel)
  end

  # The guard itself. CARD_TOOLS is validated at class load, so a bare
  # "tool" => "kind" entry cannot reach production; these pin that the validator
  # actually refuses one, and that the shipped map is fully declared.
  describe "the CARD_TOOLS declaration guard" do
    it "refuses a CARD_TOOLS entry that is not a declaration" do
      expect {
        Ai::CardPayloadDeclaration.validate_map!("zz_undeclared_card_tool" => "some_card_kind")
      }.to raise_error(Ai::CardPayloadDeclaration::UndeclaredCardPayload, /zz_undeclared_card_tool/)
    end

    it "refuses a declaration with no field allowlist" do
      expect { Ai::CardPayloadDeclaration.new(kind: "k", fields: []) }
        .to raise_error(Ai::CardPayloadDeclaration::UndeclaredCardPayload, /non-empty `fields`/)
    end

    # The one way to defeat the projection without touching the projector:
    # #project_fields assigns in order, so a bare entry after a nested one for the
    # same key would overwrite the bound and copy the whole subtree, while the
    # declaration still READ as bounded.
    it "refuses the same key declared twice at one level" do
      expect {
        Ai::CardPayloadDeclaration.new(kind: "k", fields: [{ "gate" => %w[disposition] }, "gate"])
      }.to raise_error(Ai::CardPayloadDeclaration::UndeclaredCardPayload, /declared twice/)
    end

    it "deep-freezes the declaration so it cannot be widened at runtime" do
      decl = described_class::CARD_TOOLS.fetch("system_deploy_platform")
      nested = decl.fields.find { |f| f.is_a?(Hash) && f.key?("card") }

      expect(decl.fields).to be_frozen
      expect(nested).to be_frozen
      expect { nested["card"] << "acceptance_token" }.to raise_error(FrozenError)
    end

    it "refuses a nested declaration with no subkey allowlist" do
      expect { Ai::CardPayloadDeclaration.new(kind: "k", fields: [{ "plan" => [] }]) }
        .to raise_error(Ai::CardPayloadDeclaration::UndeclaredCardPayload, /non-empty subkey/)
    end

    it "refuses to build a card payload without a declaration at dispatch time" do
      expect { bridge.send(:card_payload_from_result, { data: { "a" => 1 } }, "provisioning_status") }
        .to raise_error(Ai::CardPayloadDeclaration::UndeclaredCardPayload, /no safe default projection/)
    end

    it "ships a map in which every tool carries a declaration" do
      expect(described_class::CARD_TOOLS.values).to all(be_a(Ai::CardPayloadDeclaration))
      expect(described_class::CARD_TOOLS).not_to be_empty
    end
  end

  # Nested projection — the leak the audit turned up on this action was
  # `adaptation_plan.steps[].inputs`, a raw execution_config jsonb into which
  # the caller's own `details:` hash is copied verbatim upstream.
  describe "nested projection" do
    let(:spec) { described_class::CARD_TOOLS["platform_provisioning_adapt"] }

    it "drops an undeclared key nested inside a declared array element" do
      payload = spec.project(
        "mission_id" => "m-1",
        "adaptation_plan" => {
          "id" => "p-1",
          "steps" => [
            { "step_number" => 1, "skill" => "scale_project",
              "inputs" => { "signal_payload" => sentinel } }
          ]
        }
      )

      expect(payload.to_json).not_to include(sentinel)
      expect(payload.dig("adaptation_plan", "steps", 0)).to eq(
        "step_number" => 1, "skill" => "scale_project"
      )
    end

    it "reads symbol keys, which is how a Ruby producer hands the result over" do
      payload = spec.project(mission_id: "m-1", change_type: "scale_out",
                             gate: { disposition: "parked", detail: sentinel })

      expect(payload).to eq("mission_id" => "m-1", "change_type" => "scale_out",
                            "gate" => { "disposition" => "parked" })
    end

    it "bounds the persisted payload by size as well as by key" do
      decl = Ai::CardPayloadDeclaration.new(kind: "k", fields: %w[blob])
      payload = decl.project("blob" => "x" * (Ai::CardPayloadDeclaration::MAX_PAYLOAD_BYTES + 1))

      expect(payload).to include("card_payload_omitted" => true, "reason" => "payload_too_large")
    end
  end
end
