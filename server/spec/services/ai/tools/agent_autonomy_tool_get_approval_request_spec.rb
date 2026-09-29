# frozen_string_literal: true

require "rails_helper"

# IMP-7f2b7b790f97 — every gated verb's pending envelope tells the caller to poll
# the approval request, and MCP had no lookup by approval_request_id or
# deferred_operation_id (list_deferred_operations filters by status and agent
# only, and omits the decision, expiry and origin). get_approval_request is that
# lookup: a pure read, account-scoped, redacted, and — for an instance principal
# — limited to the requests that principal itself parked.
RSpec.describe "agent_autonomy get_approval_request" do
  let(:tool_class) { ::Ai::Tools::AgentAutonomyTool }
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }

  let(:reader)       { create(:user, account: account, permissions: %w[ai.agents.read]) }
  let(:unprivileged) { create(:user, account: account, permissions: []) }
  let(:decider)      { create(:user, account: account, permissions: %w[ai.agents.read ai.autonomy.approve]) }

  # Built at runtime from parts, and obviously fake, so no secret scanner reads
  # this file as carrying a credential.
  let(:fake_secret) { %w[not a real secret value].join("-") }
  let(:own_instance)   { Struct.new(:id).new(SecureRandom.uuid) }
  let(:other_instance) { Struct.new(:id).new(SecureRandom.uuid) }

  before do
    ::Ai::InterventionPolicy.register_category!("test.gated_action")
    ::Ai::InterventionPolicy.create!(
      account: account, action_category: "test.gated_action",
      scope: "global", policy: "require_approval", priority: 5, is_active: true
    )
    stub_const("GetApprovalSpecExecutor", Class.new do
      def self.execute(_params, deferred_operation:) = { ok: true }
      def self.preview(_params, deferred_operation: nil) = { summary: "gated action" }
    end)
  end

  def park(acct: account, principal:, origin: nil, tool_params: {})
    ::Ai::AutonomyGate.evaluate(
      action_category: "test.gated_action",
      executor_class: "GetApprovalSpecExecutor",
      params: { "tool_class" => "Ai::Tools::SdwanTool", "action" => "x",
                "tool_params" => tool_params, "principal" => principal },
      account: acct,
      requested_by: decider,
      description: "a gated action awaiting approval",
      call_origin: origin
    ).deferred_operation
  end

  let(:user_principal) { { "kind" => "user", "user_id" => decider.id } }
  let!(:deferred) do
    park(principal: user_principal, origin: "mcp_oauth",
         tool_params: { "acceptance_token" => fake_secret, "name" => "visible" })
  end
  let(:approval_request) { deferred.approval_request }

  def run(params, user: reader)
    ::Ai::Tools::McpPlatformToolRegistrar.execute_tool(
      "platform.get_approval_request", params: params, account: account, user: user
    )
  end

  def run_as_instance(params, node_instance:)
    ::Ai::Tools::McpPlatformToolRegistrar.execute_tool(
      "platform.get_approval_request", params: params, account: account, user: nil,
                                       instance_authorized: true, node_instance: node_instance
    )
  end

  describe "lookup" do
    it "finds the request by approval_request_id" do
      result = run({ "approval_request_id" => approval_request.id })

      expect(result[:success]).to be(true)
      expect(result).to include(
        approval_request_id: approval_request.id, deferred_operation_id: deferred.id,
        status: "pending", decision: nil, decided_by: nil, decided_at: nil,
        requires_human_session: false, call_origin: "mcp_oauth", expired: false,
        action_category: "test.gated_action", description: "a gated action awaiting approval"
      )
      expect(result[:expires_at]).to eq(approval_request.expires_at&.iso8601)
      expect(result[:deferred_operation]).to include(id: deferred.id, status: "pending", error_message: nil)
    end

    it "finds the same request by deferred_operation_id" do
      result = run({ "deferred_operation_id" => deferred.id })

      expect(result[:success]).to be(true)
      expect(result[:approval_request_id]).to eq(approval_request.id)
    end

    it "reports the recorded decision and who made it" do
      approval_request.decisions.create!(approver: decider, step_number: 0, decision: "rejected",
                                         origin: "rest_session")
      approval_request.update_columns(status: "rejected", completed_at: Time.current)

      result = run({ "approval_request_id" => approval_request.id })

      expect(result).to include(status: "rejected", decision: "rejected")
      expect(result[:decided_by]).to eq(id: decider.id, name: decider.full_name)
      expect(result[:decided_at]).to be_present
    end

    it "reports an expired-but-pending request as expired without mutating it" do
      approval_request.update_columns(expires_at: 1.hour.ago)

      result = run({ "approval_request_id" => approval_request.id })

      expect(result).to include(status: "pending", expired: true)
      expect(approval_request.reload.status).to eq("pending")
    end

    it "carries the linked operation's failure" do
      deferred.update_columns(status: "failed", error_message: "RuntimeError: it broke")

      expect(run({ "approval_request_id" => approval_request.id })[:deferred_operation])
        .to include(status: "failed", error_message: "RuntimeError: it broke")
    end

    it "writes nothing" do
      expect { run({ "approval_request_id" => approval_request.id }) }
        .not_to change { [ ::Ai::ApprovalRequest.maximum(:updated_at), ::Ai::DeferredOperation.maximum(:updated_at) ] }
    end
  end

  describe "id validation" do
    it "refuses neither id" do
      result = run({})

      expect(result[:success]).to be(false)
      expect(result[:error]).to match(/exactly one of approval_request_id or deferred_operation_id/)
    end

    it "refuses both ids" do
      result = run({ "approval_request_id" => approval_request.id, "deferred_operation_id" => deferred.id })

      expect(result[:success]).to be(false)
      expect(result[:error]).to match(/exactly one of approval_request_id or deferred_operation_id/)
    end

    it "answers an unknown id with a literal not-found" do
      result = run({ "approval_request_id" => SecureRandom.uuid })

      expect(result).to eq(success: false, error: "Approval request not found")
    end

    it "answers a malformed id with the same not-found, not a driver error" do
      expect(run({ "approval_request_id" => "not-a-uuid" }))
        .to eq(success: false, error: "Approval request not found")
    end
  end

  describe "account scoping" do
    let(:foreign_deferred) { park(acct: other_account, principal: user_principal) }

    before do
      ::Ai::InterventionPolicy.create!(
        account: other_account, action_category: "test.gated_action",
        scope: "global", policy: "require_approval", priority: 5, is_active: true
      )
    end

    it "answers a cross-account approval_request_id with not-found" do
      result = run({ "approval_request_id" => foreign_deferred.approval_request.id })

      expect(result).to eq(success: false, error: "Approval request not found")
    end

    it "answers a cross-account deferred_operation_id with the identical not-found" do
      result = run({ "deferred_operation_id" => foreign_deferred.id })

      expect(result).to eq(success: false, error: "Approval request not found")
      expect(result.to_s).not_to include(account.id, other_account.id)
    end
  end

  describe "redaction" do
    it "masks secret-keyed params in request_data and the operation's own params" do
      result = run({ "approval_request_id" => approval_request.id })

      expect(result.to_json).not_to include(fake_secret)
      expect(result[:request_data].dig("params", "tool_params", "acceptance_token")).to eq("[FILTERED]")
      expect(result[:request_data].dig("params", "tool_params", "name")).to eq("visible")
      expect(result[:deferred_operation][:params].dig("tool_params", "acceptance_token")).to eq("[FILTERED]")
    end

    it "masks a secret inside a stored request_data written before the gate redacted" do
      approval_request.update_columns(request_data: approval_request.request_data.merge("api_key" => fake_secret))

      expect(run({ "approval_request_id" => approval_request.id }).to_json).not_to include(fake_secret)
    end

    it "masks a secret carried in an operation's raw exception text" do
      deferred.update_columns(
        status: "failed",
        error_message: "ActiveRecord::RecordInvalid: bad {\"acceptance_token\"=>\"#{fake_secret}\"} and " \
                       "password=#{fake_secret}; Authorization: Bearer #{fake_secret}"
      )
      approval_request.update_columns(execution_status: "failed",
                                      execution_error: "RuntimeError: token: #{fake_secret}")

      result = run({ "approval_request_id" => approval_request.id })

      expect(result.to_json).not_to include(fake_secret)
      expect(result[:deferred_operation][:error_message]).to start_with("ActiveRecord::RecordInvalid")
      expect(result[:execution_error]).to start_with("RuntimeError")
    end

    it "bounds a long error message" do
      deferred.update_columns(status: "failed", error_message: "RuntimeError: #{'x' * 5_000}")

      expect(run({ "approval_request_id" => approval_request.id })[:deferred_operation][:error_message].length)
        .to be <= ::Ai::SensitiveParams::TEXT_LIMIT
    end
  end

  describe "instance principal scoping" do
    let!(:own_op) do
      park(principal: { "kind" => "instance", "node_instance_id" => own_instance.id }, origin: "mcp_instance")
    end
    let!(:others_op) do
      park(principal: { "kind" => "instance", "node_instance_id" => other_instance.id }, origin: "mcp_instance")
    end
    let!(:user_op) { deferred }

    it "serves a request the instance itself parked, by either id" do
      by_request = run_as_instance({ "approval_request_id" => own_op.approval_request.id }, node_instance: own_instance)
      by_op      = run_as_instance({ "deferred_operation_id" => own_op.id }, node_instance: own_instance)

      expect(by_request[:success]).to be(true)
      expect(by_op[:approval_request_id]).to eq(own_op.approval_request.id)
    end

    it "answers another instance's request with the same not-found as a foreign account" do
      by_request = run_as_instance({ "approval_request_id" => others_op.approval_request.id }, node_instance: own_instance)
      by_op      = run_as_instance({ "deferred_operation_id" => others_op.id }, node_instance: own_instance)
      unknown    = run_as_instance({ "approval_request_id" => SecureRandom.uuid }, node_instance: own_instance)

      expect(by_request).to eq(success: false, error: "Approval request not found")
      expect(by_op).to eq(by_request)
      expect(unknown).to eq(by_request)
    end

    it "answers a request a person or agent parked, which no instance originated" do
      expect(run_as_instance({ "approval_request_id" => user_op.approval_request.id }, node_instance: own_instance))
        .to eq(success: false, error: "Approval request not found")
    end

    it "fails closed for a restricted principal with no node instance" do
      expect(run_as_instance({ "approval_request_id" => own_op.approval_request.id }, node_instance: nil))
        .to eq(success: false, error: "Approval request not found")
    end

    it "does not narrow a user principal, who reads through the same surface as the REST queue" do
      expect(run({ "approval_request_id" => others_op.approval_request.id })[:success]).to be(true)
    end
  end

  describe "permission" do
    it "is served at the floor, ai.agents.read, the permission the REST show_approval read demands" do
      expect(tool_class::ACTION_PERMISSIONS).not_to have_key("get_approval_request")
      expect(run({ "approval_request_id" => approval_request.id }, user: reader)[:success]).to be(true)
    end

    it "refuses a caller without ai.agents.read" do
      expect { run({ "approval_request_id" => approval_request.id }, user: unprivileged) }
        .to raise_error(::Mcp::ProtocolService::PermissionDeniedError)
    end
  end

  describe "declaration" do
    it "is a pure read" do
      declaration = tool_class.declared_action("get_approval_request")

      expect(declaration).to include(mutating: false)
      expect(declaration[:destructive]).to be_falsey
    end
  end
end
