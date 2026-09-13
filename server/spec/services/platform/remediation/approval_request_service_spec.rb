# frozen_string_literal: true

require "rails_helper"

# Platform::Remediation::ApprovalRequestService — the account scope on the
# dedupe lookup, both arms (E2 review L2).
#
# The A5 review's L2 changed `account.id` to `account&.id` in #find_active and
# nothing asserted it. Two separate properties ride on that one line:
#
#   SCOPING      the dedupe lookup never reaches another account's request. A
#                request account B parked for a component, kind and fingerprint
#                must not satisfy account A's identical request — answering A
#                with B's card hands A an id it cannot see and parks nothing in
#                front of A's operator.
#
#   NO ACCOUNT   an accountless caller fails on the path the tool already
#                reports. `account.id` raised NoMethodError inside the lookup,
#                and PlatformRemediationTool#request_approval rescues only
#                RecordInvalid, so it escaped unhandled. With safe navigation
#                the lookup finds nothing and the chain build refuses the
#                accountless chain with RecordInvalid, which the tool reports.
RSpec.describe Platform::Remediation::ApprovalRequestService do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:component) do
    create(:platform_component_status, account: account,
                                       component_kind: "node_instance", component_ref: "inst-l2",
                                       display_name: "Instance L2", verdict: Platform::ComponentStatus::DOWN)
  end
  let(:args) do
    { component_status: component, signal_kind: "instance.silent",
      rationale: "restart it", fingerprint: "occ-1" }
  end

  describe "the account scope on the dedupe lookup" do
    # THE CONTROL for the cross-account example: within one account the same
    # occurrence dedupes. Without it, the next example could pass because
    # dedupe is simply broken.
    it "reuses a live request for the same occurrence in the same account" do
      first = described_class.new(account: account).request!(**args)
      second = described_class.new(account: account).request!(**args)

      expect(first.deduplicated?).to be(false)
      expect(second.deduplicated?).to be(true)
      expect(second.approval_request.id).to eq(first.approval_request.id)
    end

    it "does not reuse another account's live request for the same occurrence" do
      foreign = described_class.new(account: other_account).request!(**args)
      own = described_class.new(account: account).request!(**args)

      expect(foreign.approval_request.account_id).to eq(other_account.id)
      expect(own.deduplicated?).to be(false)
      expect(own.approval_request.id).not_to eq(foreign.approval_request.id)
      expect(own.approval_request.account_id).to eq(account.id)
    end
  end

  # MCP identity plan D1: this service mints its request outside
  # Ai::AutonomyGate, so it records the door itself, the way the gate does.
  # Without that mark the approval guards read the request as a person's own.
  describe "the door the request came through" do
    it "records the tool door and the requesting agent, so the guards see a tool-door request" do
      agent = create(:ai_agent, account: account)

      request = described_class.new(account: account)
                               .request!(**args, call_origin: "agent_bridge", agent: agent).approval_request

      expect(request.request_data).to include("call_origin" => "agent_bridge", "agent_id" => agent.id)
      expect(request.tool_door_request?).to be(true)
      expect(request.requester_excluded?(approver: nil, origin: "agent_bridge", agent: agent)).to be(true)
    end

    it "leaves an unmarked call unmarked, so a person's own request keeps today's rule" do
      request = described_class.new(account: account).request!(**args).approval_request

      expect(request.request_data.keys).not_to include("call_origin", "agent_id")
      expect(request.tool_door_request?).to be(false)
    end

    it "refuses a door outside the vocabulary" do
      expect { described_class.new(account: account).request!(**args, call_origin: "carrier_pigeon") }
        .to raise_error(ArgumentError, /unknown call_origin "carrier_pigeon"/)
    end
  end

  describe "an accountless caller" do
    it "fails with RecordInvalid from the chain build, not NoMethodError from the lookup" do
      expect {
        described_class.new(account: nil).request!(**args)
      }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end
end
