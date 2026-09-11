# frozen_string_literal: true

require "rails_helper"

# L9. A human-only action replays AS the person whose own-session approval
# completes its request, so that approval is refused, by the decider's name,
# when the decider lacks the permission the action runs under. Before, it was
# recorded: the request was spent, and the replay refused it naming the
# principal that asked for it rather than the person who approved.
RSpec.describe "A completing approval by a person without the action's permission (L9)", type: :request do
  let(:account) { create(:account) }
  let!(:requester) { user_with_permissions("ai.agents.read", "ai.agents.manage", "ai.autonomy.approve", account: account) }
  let(:holder) { user_with_permissions("ai.agents.read", "ai.agents.manage", "ai.autonomy.approve", account: account) }
  # Holds the tool's floor, not the action's own permission: the check is the
  # action's (ACTION_PERMISSIONS, as the MCP door resolves it), not the floor.
  let(:bystander) { user_with_permissions("ai.agents.read", "ai.autonomy.approve", account: account) }
  let(:sightings) { [] }

  let(:tool_class) do
    seen = sightings
    klass = Class.new(::Ai::Tools::BaseTool) do
      def self.definition
        { name: "spec_l9_tool", description: "human-only probe",
          parameters: { action: { type: "string", required: false } } }
      end

      declare_action "spec_l9_write",
                     mutating: true, human_only: true,
                     action_category: "spec.l9.write",
                     executor_class: "Ai::Executors::DeferredToolCall",
                     gate_context: :deferred_tool_call_context,
                     on_proceed: :deferred_tool_call_result

      define_method(:call) do |_params|
        seen << { user_id: user&.id, agent_id: agent&.id }
        success_result(ran: true)
      end
    end
    klass.const_set(:REQUIRED_PERMISSION, "ai.agents.read")
    klass.const_set(:ACTION_PERMISSIONS, { "spec_l9_write" => "ai.agents.manage" }.freeze)
    stub_const("SpecL9Tool", klass)
  end

  before do
    Ai::InterventionPolicy.register_category!("spec.l9.write")
    tool_class
  end

  # Parked the way a person's Claude Code parks it: their OAuth token, no agent.
  def park!
    tool = SpecL9Tool.new(account: account, user: requester)
    tool.call_origin = "mcp_oauth"
    result = tool.execute(params: { action: "spec_l9_write" })
    expect(result[:data]).to include(pending: true, requires_human_session: true)
    Ai::ApprovalRequest.find(result[:data][:approval_request_id])
  end

  def rest_approve!(request, user)
    post "/api/v1/ai/autonomy/approvals/#{request.id}/approve", headers: auth_headers_for(user), as: :json
  end

  it "refuses the decider's own-session approval with 403, naming the decider, and leaves the request pending" do
    request = park!

    rest_approve!(request, bystander)

    expect(response).to have_http_status(:forbidden)
    expect(json_response["error"]).to include(bystander.email, "ai.agents.manage")
    expect(request.reload.status).to eq("pending")
    expect(request.decisions.count).to eq(0)
    expect(sightings).to be_empty
  end

  it "lets a person who holds the permission complete the same request, and it runs as them" do
    request = park!
    rest_approve!(request, bystander)

    rest_approve!(request, holder)

    expect(response).to have_http_status(:ok)
    expect(request.reload.status).to eq("approved")
    expect(sightings).to eq([ { user_id: holder.id, agent_id: nil } ])
  end
end
