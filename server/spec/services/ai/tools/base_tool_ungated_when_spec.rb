# frozen_string_literal: true

require "rails_helper"

# HIER-P2B-ENG — `ungated_when:` on a gate-routed declaration.
#
# A mutating action can carry a READ-shaped arm: system_deploy_platform with
# no `mode` returns the deployment wizard card and provisions nothing. Once
# the action is gate-routed, every call would meet the gate — and a
# require_approval row would park a form read as an approval. The
# declaration may therefore name ONE predicate, resolved on the tool
# instance, that says "this particular call is the read arm: dispatch it to
# #call exactly as an ungated action". Everything else about the declaration
# is unchanged, and the completeness census still counts the action as
# gate-routed.
#
# Fail CLOSED by construction: a predicate the tool does not define never
# opens the arm (the call stays gated), and the arm is decided from the
# tool's own method, never from anything the caller supplies by name.
RSpec.describe Ai::Tools::BaseTool, "ungated_when" do
  let(:account) { create(:account) }

  before do
    stub_const("ZzUngatedWhenFixtureTool", Class.new(Ai::Tools::BaseTool) do
      declare_action "zz_ungated_when_fixture",
                     mutating: true,
                     action_category: "zz.ungated_when_fixture",
                     executor_class: "Ai::Executors::DeferredToolCall",
                     gate_context: :deferred_tool_call_context,
                     on_proceed: :deferred_tool_call_result,
                     ungated_when: :read_arm?

      def self.definition
        {
          name: "zz_ungated_when_fixture",
          description: "ungated_when fixture",
          parameters: { action: { type: "string", required: true }, mode: { type: "string", required: false } }
        }
      end

      def read_arm?(params)
        params[:mode].blank?
      end

      def call(params)
        success_result(called: true, mode: params[:mode])
      end
    end)
  end

  let(:tool) { ZzUngatedWhenFixtureTool.new(account: account, internal: true) }

  def run(**params)
    tool.execute(params: { action: "zz_ungated_when_fixture" }.merge(params).with_indifferent_access)
  end

  it "records the predicate on the declaration and still counts the action as gate-routed" do
    declaration = ZzUngatedWhenFixtureTool.declared_action("zz_ungated_when_fixture")

    expect(declaration[:ungated_when]).to eq(:read_arm?)
    expect(tool.send(:gated_action?, declaration)).to be(true)
  end

  it "dispatches the read arm straight to #call — no gate, no deferred operation" do
    expect(Ai::AutonomyGate).not_to receive(:evaluate)

    result = run

    expect(result[:success]).to be(true)
    expect(result[:data][:called]).to be(true)
    expect(Ai::DeferredOperation.where(account_id: account.id)).to be_empty
  end

  it "gates every other call of the same action" do
    expect(Ai::AutonomyGate).to receive(:evaluate).and_call_original

    result = run(mode: "standalone")

    expect(result[:success]).to be(true)
    expect(result[:data][:pending]).to be(true) # unmatched category -> require_approval default
    expect(Ai::DeferredOperation.where(account_id: account.id).count).to eq(1)
  end

  it "fails closed when the predicate is not defined on the tool: the call stays gated" do
    ZzUngatedWhenFixtureTool.declare_action "zz_ungated_when_fixture",
                                            mutating: true,
                                            action_category: "zz.ungated_when_fixture",
                                            executor_class: "Ai::Executors::DeferredToolCall",
                                            gate_context: :deferred_tool_call_context,
                                            on_proceed: :deferred_tool_call_result,
                                            ungated_when: :no_such_predicate?

    result = run

    expect(result[:data][:pending]).to be(true)
  end
end
