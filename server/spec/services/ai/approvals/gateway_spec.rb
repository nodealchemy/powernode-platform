# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Approvals::Gateway do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:approvable) { create(:ai_agent, account: account) }

  subject(:gateway) { described_class.new(account: account) }

  describe "#request! in core mode (no governance)" do
    before { allow(Ai::Autonomy::ApprovalWorkflowService).to receive(:governance_enabled?).and_return(false) }

    it "auto-proceeds without creating an approval request" do
      result = nil
      expect { result = gateway.request!(approvable: approvable, kind: "merge_approval") }
        .not_to change(Ai::ApprovalRequest, :count)

      expect(result).to be_proceed
      expect(result.approval_request).to be_nil
    end
  end

  describe "#request! with governance enabled" do
    before { allow(Ai::Autonomy::ApprovalWorkflowService).to receive(:governance_enabled?).and_return(true) }

    it "creates a pending approval request targeting the approvable" do
      result = gateway.request!(approvable: approvable, kind: "merge_approval", description: "Land it")

      expect(result).to be_pending
      req = result.approval_request
      expect(req.source_type).to eq("Ai::Agent")
      expect(req.source_id).to eq(approvable.id)
      expect(req.request_data["action_type"]).to eq("merge_approval")
      expect(req).to be_pending
    end

    it "reuses one chain per kind" do
      gateway.request!(approvable: approvable, kind: "merge_approval")
      gateway.request!(approvable: approvable, kind: "merge_approval")

      expect(Ai::ApprovalChain.where(account: account, name: "gateway_merge_approval").count).to eq(1)
    end

    it "supports second-signature gates via required_approvals" do
      result = gateway.request!(approvable: approvable, kind: "release", required_approvals: 2)

      expect(result.approval_request.approval_chain.steps.first["required_approvals"]).to eq(2)
    end

    # IMP-<approvalchain-strengthen> — find_or_create_chain used find_or_create_by!
    # with a block that only runs on the FIRST call ever made for a given
    # (account, "gateway_#{kind}") pair. Every later call silently reused the
    # existing chain, discarding whatever required_approvals/approvers the
    # caller just asked for -- no error, no log. A caller demanding a second
    # signature got a single-approver chain back. These pin the strengthen-only
    # fix: never fewer approvals/narrower approvers than requested, never
    # weaker than what already exists either.
    describe "chain reuse is strengthen-only" do
      it "strengthens required_approvals on an existing chain rather than discarding the higher ask" do
        gateway.request!(approvable: approvable, kind: "deploy") # first call: required_approvals defaults to 1
        result = gateway.request!(approvable: approvable, kind: "deploy", required_approvals: 2)

        expect(Ai::ApprovalChain.where(account: account, name: "gateway_deploy").count).to eq(1)
        expect(result.approval_request.approval_chain.steps.first["required_approvals"]).to eq(2)
      end

      it "never weakens an existing chain's required_approvals on a later, lower-required call" do
        gateway.request!(approvable: approvable, kind: "rollback", required_approvals: 2)
        result = gateway.request!(approvable: approvable, kind: "rollback") # required_approvals defaults to 1

        expect(result.approval_request.approval_chain.steps.first["required_approvals"]).to eq(2)
      end

      it "strengthens approvers from the universal set to a requested narrower one" do
        gateway.request!(approvable: approvable, kind: "publish") # approvers defaults to ["*"]
        result = gateway.request!(approvable: approvable, kind: "publish", approvers: [ user.id ])

        expect(result.approval_request.approval_chain.steps.first["approvers"]).to eq([ user.id ])
      end

      it "never widens an existing chain's approvers back to the universal set" do
        gateway.request!(approvable: approvable, kind: "revoke", approvers: [ user.id ])
        result = gateway.request!(approvable: approvable, kind: "revoke") # approvers defaults to ["*"]

        expect(result.approval_request.approval_chain.steps.first["approvers"]).to eq([ user.id ])
      end

      it "logs when a stored chain was weaker than requested and gets strengthened" do
        gateway.request!(approvable: approvable, kind: "escalate")
        expect(Rails.logger).to receive(:warn).with(/weaker than requested/)

        gateway.request!(approvable: approvable, kind: "escalate", required_approvals: 2)
      end

      it "does not log when the stored chain already meets the request" do
        gateway.request!(approvable: approvable, kind: "noop_reuse", required_approvals: 2)
        expect(Rails.logger).not_to receive(:warn)

        gateway.request!(approvable: approvable, kind: "noop_reuse", required_approvals: 1)
      end

      # A narrower instance of the same defect: two non-wildcard approver
      # sets that differ, with neither comparably weaker/stronger than the
      # other (approvers_at_least_as_strong? correctly refuses to invent an
      # ordering between them, so the stored set wins). Before this, that
      # path fell through the same `return if approvers_ok && required_ok`
      # early-return as the fully-satisfied case, so a caller's specific,
      # different approver request was discarded with no error and no log
      # -- silent discard of a caller-supplied authorization parameter,
      # same shape as the original bug, just not a weakening.
      it "keeps the stored approvers when the request differs but is not weaker, and surfaces the divergence" do
        gateway.request!(approvable: approvable, kind: "handoff", approvers: [ "operator-a" ])
        expect(Rails.logger).to receive(:info).with(/kept its stored approvers/)

        result = gateway.request!(approvable: approvable, kind: "handoff", approvers: [ "operator-b" ])

        expect(result.approval_request.approval_chain.steps.first["approvers"]).to eq([ "operator-a" ])
      end
    end
  end

  describe "#resolve!" do
    before { allow(Ai::Autonomy::ApprovalWorkflowService).to receive(:governance_enabled?).and_return(true) }

    let(:request) { gateway.request!(approvable: approvable, kind: "merge_approval").approval_request }

    it "records an approval decision through the workflow service" do
      expect(gateway.resolve!(request: request, decision: "approved", by: user)).to be true
      expect(request.reload.status).to eq("approved")
    end

    it "records a rejection" do
      expect(gateway.resolve!(request: request, decision: "rejected", by: user)).to be true
      expect(request.reload.status).to eq("rejected")
    end

    it "raises on an invalid decision" do
      expect { gateway.resolve!(request: request, decision: "maybe", by: user) }.to raise_error(ArgumentError)
    end
  end
end
