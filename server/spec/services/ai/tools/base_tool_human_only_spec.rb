# frozen_string_literal: true

require "rails_helper"

# MCP identity plan R2: "MCP requests, a person confirms."
#
# A human_only action called through ANY tool door neither runs nor is refused.
# It PARKS the exact call through the existing gate (Ai::AutonomyGate pending
# envelope, Ai::Executors::DeferredToolCall, Ai::ApprovalRequest), flagged
# requires_human_session, whatever an intervention policy says. Only a decision
# from a person's OWN session completes it, and the replay then runs AS that
# person. Every example asserts both arms: the park and the body that never ran,
# or the run and who it ran as.
RSpec.describe "BaseTool human_only actions (MCP identity plan R2)" do
  let(:account) { create(:account) }
  let!(:requester) { create(:user, account: account) }
  let(:confirmer) { create(:user, account: account, permissions: [ "ai.agents.manage", "ai.autonomy.approve" ]) }
  let(:agent) { create(:ai_agent, account: account) }
  let(:sightings) { [] }

  let(:tool_class) do
    seen = sightings
    klass = Class.new(::Ai::Tools::BaseTool) do
      def self.definition
        {
          name: "spec_human_tool",
          description: "human-only probe",
          parameters: { action: { type: "string", required: false } }
        }
      end

      declare_action "spec_human_write",
                     mutating: true, human_only: true,
                     action_category: "spec.human.write",
                     executor_class: "Ai::Executors::DeferredToolCall",
                     gate_context: :deferred_tool_call_context,
                     on_proceed: :deferred_tool_call_result
      declare_action "spec_plain_write", mutating: true

      define_method(:call) do |params|
        seen << { action: params[:action].to_s, user_id: user&.id, agent_id: agent&.id }
        success_result(ran: true)
      end
    end
    klass.const_set(:REQUIRED_PERMISSION, "ai.agents.manage")
    stub_const("SpecHumanTool", klass)
  end

  before do
    Ai::InterventionPolicy.register_category!("spec.human.write")
    # The strongest policy there is: without R2 this call would simply run.
    Ai::InterventionPolicy.create!(
      account: account, action_category: "spec.human.write",
      scope: "global", policy: "auto_approve", priority: 5, is_active: true
    )
    tool_class
  end

  after { ::Mcp::Principal.reset! }

  def tool_for(origin:, user: nil, agent: nil, internal: false)
    tool = SpecHumanTool.new(account: account, user: user, agent: agent, internal: internal)
    tool.call_origin = origin if origin
    tool
  end

  def park!(tool)
    result = tool.execute(params: { action: "spec_human_write", note: "keep" })
    expect(result).to include(success: true)
    expect(result[:data]).to include(pending: true, requires_human_session: true)
    expect(result[:data][:approval_request_id]).to be_present
    expect(result[:data][:message]).to include("approval queue")
    Ai::DeferredOperation.find(result[:data][:deferred_operation_id])
  end

  def workflow = Ai::Autonomy::ApprovalWorkflowService.new(account: account)

  describe "parking" do
    it "parks from every tool door and from an unmarked call, and never runs, even under auto_approve" do
      (Ai::Tools::CallOrigin::ALL + [ nil ]).each do |origin|
        operation = park!(tool_for(origin: origin, user: requester))

        expect(operation.status).to eq("pending")
        expect(operation.approval_request.requires_human_session?).to be(true)
        expect(operation.params["human_only"]).to be(true)
      end
      expect(sightings).to be_empty
    end

    it "parks for an agent alone, an internal caller, and a restricted principal with no instance" do
      park!(tool_for(origin: "agent_bridge", agent: agent))
      park!(tool_for(origin: nil, internal: true))
      federation_like = tool_for(origin: "mcp_federation")
      federation_like.instance_authorized = true
      park!(federation_like)

      expect(sightings).to be_empty
    end

    it "records who asked on the request (the requester, and the agent when there is one)" do
      operation = park!(tool_for(origin: "mcp_oauth", user: requester, agent: agent))

      expect(operation.requested_by_id).to eq(requester.id)
      expect(operation.ai_agent_id).to eq(agent.id)
      expect(operation.params["principal"]).to include("kind" => "user", "user_id" => requester.id)
    end

    it "still lets a block policy block (stricter than parking)" do
      Ai::InterventionPolicy.where(action_category: "spec.human.write").update_all(policy: "block")

      result = tool_for(origin: "mcp_oauth", user: requester).execute(params: { action: "spec_human_write" })

      expect(result[:success]).to be(false)
      expect(Ai::ApprovalRequest.count).to eq(0)
      expect(sightings).to be_empty
    end

    it "leaves a plain declared action on the same tool running directly (the other arm)" do
      result = tool_for(origin: "mcp_oauth", user: requester).execute(params: { action: "spec_plain_write" })

      expect(result).to include(success: true, data: { ran: true })
      expect(sightings).to eq([ { action: "spec_plain_write", user_id: requester.id, agent_id: nil } ])
      expect(Ai::DeferredOperation.count).to eq(0)
    end
  end

  describe "who may complete it" do
    it "runs AS the person who approves from their own session, with no agent" do
      operation = park!(tool_for(origin: "mcp_oauth", user: requester, agent: agent))

      expect(workflow.approve(request: operation.approval_request, approver: confirmer,
                              origin: Ai::ApprovalDecision::REST_SESSION)).to be(true)

      expect(sightings).to eq([ { action: "spec_human_write", user_id: confirmer.id, agent_id: nil } ])
      expect(operation.reload.status).to eq("completed")
    end

    it "lets the requester confirm from their own session (a solo owner), and runs as them" do
      operation = park!(tool_for(origin: "mcp_oauth", user: requester))

      expect(workflow.approve(request: operation.approval_request, approver: requester,
                              origin: Ai::ApprovalDecision::REST_SESSION)).to be(true)

      expect(sightings).to eq([ { action: "spec_human_write", user_id: requester.id, agent_id: nil } ])
    end

    it "refuses a decision from a tool door, from a non-own REST session, and from a caller naming no door" do
      operation = park!(tool_for(origin: "mcp_oauth", user: requester))
      request = operation.approval_request

      [ "mcp_oauth", "agent_bridge", Ai::ApprovalDecision::REST_OTHER, nil ].each do |origin|
        expect(workflow.approve(request: request, approver: confirmer, origin: origin)).to be(false)
        expect(workflow.reject(request: request, approver: confirmer, origin: origin)).to be(false)
      end

      expect(request.reload.status).to eq("pending")
      expect(request.decisions.count).to eq(0)
      expect(sightings).to be_empty
    end

    it "runs nothing when the request is approved with no person's decision (a timeout approval)" do
      operation = park!(tool_for(origin: "mcp_oauth", user: requester))

      operation.approval_request.update!(status: "approved")

      expect(sightings).to be_empty
      expect(operation.reload.result).to include("refused" => true, "reason" => "human_confirmation_missing")
    end

    it "refuses an approved replay built for anyone but the confirming person, without parking again" do
      operation = park!(tool_for(origin: "mcp_oauth", user: requester))
      workflow.approve(request: operation.approval_request, approver: confirmer,
                       origin: Ai::ApprovalDecision::REST_SESSION)
      sightings.clear
      operation.update_column(:status, "approved")

      impostor = tool_for(origin: nil, user: requester)
      impostor.replaying_operation = operation

      expect { @result = impostor.execute(params: { action: "spec_human_write" }) }
        .not_to change(Ai::DeferredOperation, :count)
      expect(@result[:success]).to be(false)
      expect(sightings).to be_empty
    end
  end

  describe ".declare_action" do
    it "refuses human_only without the gate wiring it parks through" do
      expect do
        Class.new(::Ai::Tools::BaseTool) { declare_action "x", mutating: true, human_only: true }
      end.to raise_error(ArgumentError, /human_only: true needs mutating: true and the full gate wiring/)
    end

    it "refuses human_only with an ungated_when read arm" do
      expect do
        Class.new(::Ai::Tools::BaseTool) do
          declare_action "x", mutating: true, human_only: true, action_category: "c",
                              executor_class: "Ai::Executors::DeferredToolCall",
                              gate_context: :g, on_proceed: :o, ungated_when: :u
        end
      end.to raise_error(ArgumentError, /no ungated_when/)
    end
  end
end
