# frozen_string_literal: true

require "rails_helper"

# Environment campaign, increment 4 — the operator's knobs on a plane.
#
# environment_update rewrites the governance of everything placed in a plane
# (publish-following vs pinned, blast radius, approval-required categories,
# protection), so it is HUMAN-ONLY: from any tool door — a user's connector, an
# agent, or a fleet instance principal (which skips the per-user permission
# check entirely) — it PARKS, and only a person's own-session approval runs it,
# AS that person, who must hold ai.governance.manage. Every example asserts both
# arms: the park and the row that did not change, or the run and what changed.
RSpec.describe Ai::Tools::EnvironmentTool do
  let(:account) { create(:account) }
  let(:user)    { create(:user, account: account) }
  let(:tool)    { described_class.new(account: account, user: user) }
  let(:approver) do
    create(:user, account: account, permissions: [ "ai.governance.manage", "ai.governance.read", "ai.autonomy.approve" ])
  end

  def call(action, **rest) = tool.execute(params: { action: action }.merge(rest))

  def ops = account.environments.find_by!(slug: "ops")

  def workflow = Ai::Autonomy::ApprovalWorkflowService.new(account: account)

  def park!(result)
    expect(result).to include(success: true)
    expect(result[:data]).to include(pending: true, requires_human_session: true, action_category: "ai.environment.write")
    Ai::DeferredOperation.find(result[:data][:deferred_operation_id])
  end

  def approve!(operation, as: approver)
    expect(workflow.approve(request: operation.approval_request, approver: as,
                            origin: Ai::ApprovalDecision::REST_SESSION)).to be(true)
    operation.reload
  end

  it "lists the ladder in order with every knob and each rung's predecessor" do
    r = call("environment_list")
    expect(r[:success]).to be true
    rows = r.dig(:data, :environments)
    expect(rows.map { |e| e[:slug] }).to eq(%w[dev ci staging ops prod])
    prod = rows.last
    expect(prod).to include(auto_promote_on_publish: false, is_protected: true, ladder_predecessor_slug: "staging",
                            max_blast_radius: nil, default_decision_authority: "supervised")
    expect(r.dig(:data, :scope)).to eq("account")
  end

  describe "environment_update is human-only" do
    it "parks a user's update and changes nothing until a person approves" do
      operation = park!(call("environment_update", environment: "ops", max_blast_radius: 2))

      expect(operation.status).to eq("pending")
      expect(operation.approval_request.requires_human_session?).to be(true)
      expect(ops.max_blast_radius).to be_nil
    end

    it "parks an instance principal's update (which skips the per-user permission check) and changes nothing" do
      instance_tool = described_class.new(account: account)
      instance_tool.call_origin = Ai::Tools::CallOrigin::MCP_INSTANCE
      instance_tool.instance_authorized = true

      operation = park!(instance_tool.execute(params: { "action" => "environment_update", "environment" => "ops",
                                                        "auto_promote_on_publish" => false }.with_indifferent_access))

      expect(operation.approval_request.requires_human_session?).to be(true)
      expect(ops.follows_publish?).to be true
    end

    it "runs AS the approving person and applies exactly the keys given, keeping a string-keyed false" do
      operation = park!(tool.execute(params: { "action" => "environment_update", "environment" => "ops",
                                               "auto_promote_on_publish" => false,
                                               "approval_required_categories" => [ "release.*" ] }.with_indifferent_access))

      approve!(operation)

      expect(operation.status).to eq("completed")
      expect(ops.follows_publish?).to be false
      expect(ops.approval_required_categories).to eq([ "release.*" ])
      expect(ops.max_blast_radius).to be_nil
    end

    it "addresses a plane by id as well as slug" do
      operation = park!(call("environment_update", environment: ops.id, max_blast_radius: 3))
      approve!(operation)
      expect(ops.max_blast_radius).to eq(3)
    end

    it "refuses a completing approval from a person without ai.governance.manage and leaves it pending" do
      operation = park!(call("environment_update", environment: "ops", max_blast_radius: 2))
      bystander = create(:user, account: account, permissions: [ "ai.autonomy.approve" ])

      expect(workflow.approve(request: operation.approval_request, approver: bystander,
                              origin: Ai::ApprovalDecision::REST_SESSION)).to be(false)

      expect(operation.reload.status).to eq("pending")
      expect(ops.max_blast_radius).to be_nil
    end

    it "refuses up front, without parking, a user who lacks ai.governance.manage" do
      reader = described_class.new(account: account,
                                   user: create(:user, account: account, permissions: [ "ai.governance.read" ]))
      expect(reader.execute(params: { action: "environment_list" })[:success]).to be true

      expect { @denied = reader.execute(params: { action: "environment_update", environment: "dev", max_blast_radius: 1 }) }
        .not_to change(Ai::DeferredOperation, :count)
      expect(@denied[:success]).to be false
      expect(@denied[:error]).to include("ai.governance.manage")
    end

    it "refuses an unknown plane and another account's at the gate, without parking" do
      foreign = create(:account).environments.find_by!(slug: "prod")
      [ "moon", foreign.id ].each do |target|
        expect { @refused = call("environment_update", environment: target, max_blast_radius: 1) }
          .not_to change(Ai::DeferredOperation, :count)
        expect(@refused[:success]).to be(false), "#{target.inspect} was not refused"
      end
      expect(foreign.reload.max_blast_radius).to be_nil
    end

    it "still refuses bad input at replay: an invalid value and an empty update" do
      [
        [ { environment: "dev", default_decision_authority: "yolo" }, "refused" ],
        [ { environment: "dev" }, "nothing to update" ]
      ].each do |args, message|
        operation = approve!(park!(call("environment_update", **args)))
        expect(operation.result.to_s).to include(message), "#{args.inspect} replayed to #{operation.result.inspect}"
      end
      expect(account.environments.find_by!(slug: "dev").default_decision_authority).not_to eq("yolo")
    end
  end
end
