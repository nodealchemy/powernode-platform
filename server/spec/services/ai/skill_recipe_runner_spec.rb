# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::SkillRecipeRunner do
  let(:account) { create(:account) }
  let(:user)    { create(:user, account: account) }
  let(:agent)   { create(:ai_agent, account: account) }

  let(:recipe_skill) do
    create(:ai_skill, account: account, metadata: {
      "recipe" => {
        "version" => "1",
        "inputs"  => [],
        "steps"   => [
          { "id" => "step1", "tool" => "system_list_nodes", "params" => {} }
        ],
        "output" => {}
      }
    })
  end

  let(:tool_instance) { instance_double(Ai::Tools::SystemFleetTool) }

  # dispatch_tool's principal guard (IMP-81f9fda0d5e2, sibling of the
  # per-tool fail-closed fix IMP-9030413bc292). Pins two things at once:
  #
  #   1. a run with neither a user nor an agent is refused BEFORE the tool
  #      class is ever touched — not left to fall through to a downstream
  #      "permission denied" from the tool itself.
  #   2. a run with a legitimate principal (user, or agent alone) reaches
  #      the tool constructor with EXACTLY {account:, user:, agent:} — the
  #      exact-kwargs `.with` match below fails if `internal:` (or any other
  #      stray kwarg) is ever added to that call.
  describe "#dispatch_tool principal guard" do
    context "when the run has neither a user nor an agent" do
      it "refuses to dispatch and fails the run, without constructing the tool" do
        expect(Ai::Tools::SystemFleetTool).not_to receive(:new)

        run = described_class.execute(skill: recipe_skill, inputs: {}, account: account, user: nil, agent: nil)

        expect(run.status).to eq("failed")
        expect(run.error_message).to match(/no principal/i)
        expect(run.error_message).to match(/user/i).and match(/agent/i)
      end
    end

    context "when a user principal is present (agent nil)" do
      it "dispatches, passing exactly account/user/agent — no internal: kwarg" do
        expect(Ai::Tools::SystemFleetTool).to receive(:new)
          .with(account: account, user: user, agent: nil)
          .and_return(tool_instance)
        allow(tool_instance).to receive(:execute).and_return({ success: true, data: {} })

        run = described_class.execute(skill: recipe_skill, inputs: {}, account: account, user: user, agent: nil)

        expect(run.status).to eq("completed")
      end
    end

    context "when only an agent principal is present (mcp_agent path, user nil)" do
      it "treats the agent as legitimate and dispatches — no internal: kwarg" do
        expect(Ai::Tools::SystemFleetTool).to receive(:new)
          .with(account: account, user: nil, agent: agent)
          .and_return(tool_instance)
        allow(tool_instance).to receive(:execute).and_return({ success: true, data: {} })

        run = described_class.execute(skill: recipe_skill, inputs: {}, account: account, user: nil, agent: agent)

        expect(run.status).to eq("completed")
      end
    end
  end
end
