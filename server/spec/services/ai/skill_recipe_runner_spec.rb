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

    # REWRITTEN for IMP-245d8ae56f8c. Both examples below previously stubbed
    # `SystemFleetTool.new` with exact kwargs, to pin that `internal:` never
    # leaked into the constructor. That intent is now STRUCTURAL rather than
    # asserted: dispatch_tool no longer constructs the tool at all — it calls
    # McpPlatformToolRegistrar.execute_tool — so there is no constructor call
    # here to pass `internal:` to. A constructor stub would now assert against
    # a collaborator this code does not use, which is worse than no assertion.
    context "when a user principal is present (agent nil)" do
      it "dispatches for a user holding the tool's permission" do
        permitted = create(:user, account: account,
                                  permissions: [ Ai::Tools::SystemFleetTool::REQUIRED_PERMISSION ])

        run = described_class.execute(skill: recipe_skill, inputs: {},
                                      account: account, user: permitted, agent: nil)

        expect(run.status).to eq("completed"), "a permitted user was refused: #{run.error_message}"
      end
    end

    # BEHAVIOUR CHANGE, stated rather than quietly adjusted. This example used
    # to assert that an agent-only principal DISPATCHES, on the strength of the
    # runner's comment claiming McpPlatformToolRegistrar "recognizes" a bound
    # mcp_agent. It does not: #enforce_permission! exempts only an
    # `instance_authorized` mTLS principal and otherwise raises whenever `user`
    # is nil — mcp_agent is passed to construction, never to authorization.
    #
    # Refusal is the correct outcome, not a regression. A recipe is
    # caller-supplied content; "an agent authored it" is not authority to run a
    # tool no principal can be checked against. Nothing live is affected —
    # recipe dispatch has no production entry point.
    context "when only an agent principal is present (user nil)" do
      it "reaches the gate and is refused, because an agent is not a permission" do
        run = described_class.execute(skill: recipe_skill, inputs: {},
                                      account: account, user: nil, agent: agent)

        expect(run.status).to eq("failed")
        expect(run.error_message).to match(/authentication required/i)
      end
    end
  end

  # IMP-245d8ae56f8c — REQUIRED_PERMISSION was unenforced on the recipe path.
  #
  # enforce_permission! has exactly one call site (McpPlatformToolRegistrar
  # #execute_tool) and BaseTool#execute contains no REQUIRED_PERMISSION check at
  # all, so a runner that constructed and executed the tool itself skipped the
  # only gate that reads the constant. For the 53 tool classes carrying a floor
  # and NO ACTION_PERMISSIONS map, that left them entirely ungated on this path.
  #
  # MemoryTool is deliberately the subject: floor-only ("ai.agents.read", no
  # action map), so nothing downstream re-checks and the assertion is about the
  # gate itself. SystemFleetTool — used by the examples above — carries an action
  # map, so it would keep its in-tool check and could not show this defect.
  #
  # Asserted through the REAL enforcement path with a real User and real
  # permissions. A double that stubs the tool would prove nothing: the bug is
  # that the enforcing collaborator is never reached.
  describe "REQUIRED_PERMISSION enforcement on a floor-only tool" do
    let(:memory_recipe) do
      create(:ai_skill, account: account, metadata: {
        "recipe" => {
          "version" => "1", "inputs" => [],
          "steps" => [ { "id" => "s1", "tool" => "memory_stats", "params" => {} } ],
          "output" => {}
        }
      })
    end

    it "refuses a user who lacks the tool's required permission" do
      unprivileged = create(:user, account: account, permissions: [])

      run = described_class.execute(skill: memory_recipe, inputs: {},
                                    account: account, user: unprivileged, agent: nil)

      expect(run.status).to eq("failed"),
                            "a recipe step ran a floor-only tool for a caller lacking " \
                            "#{Ai::Tools::MemoryTool::REQUIRED_PERMISSION}"
      expect(run.error_message).to match(/permission/i)
    end

    # POSITIVE CONTROL: the gate must not refuse a caller who DOES hold the
    # permission. Without this, hard-failing every dispatch would pass the
    # example above while breaking the feature outright.
    it "allows a user who holds the required permission" do
      privileged = create(:user, account: account,
                                 permissions: [ Ai::Tools::MemoryTool::REQUIRED_PERMISSION ])

      run = described_class.execute(skill: memory_recipe, inputs: {},
                                    account: account, user: privileged, agent: nil)

      expect(run.status).to eq("completed"),
                            "a permitted caller was refused: #{run.error_message}"
    end
  end
  # Blocker 2 of the recipe-dispatch readiness review — the approval gate was
  # AUTHOR-CONTROLLED. `step["require_approval"]` is read straight out of the
  # recipe, so the party the brake exists to constrain decided whether it
  # applied. Fine for trusted human-authored recipes; circular as a control on
  # caller-supplied content.
  #
  # Policy may now FORCE approval. It can only ever ADD friction: a configured
  # policy escalates, and the recipe's own flag still works, but nothing lets a
  # recipe opt OUT of a policy an operator set.
  #
  # THE PROPERTY THAT MATTERS MOST IS THE NEGATIVE ONE.
  # InterventionPolicyService#default_policy is "require_approval", so a naive
  # `resolve(...)` on every step would pause EVERY recipe on a platform where
  # nobody has written recipe policies — an approval gate that fires that
  # readily gets routed around, which is worse than the gap it closes. The
  # resolution therefore keys on whether a real policy ROW matched
  # (result[:record]), not on the returned verdict, so "unconfigured" stays
  # distinct from "configured to require approval".
  describe "policy-forced approval (step require_approval is a floor, not a ceiling)" do
    let(:plain_recipe) do
      create(:ai_skill, account: account, metadata: {
        "recipe" => {
          "version" => "1", "inputs" => [],
          # NOTE: no require_approval — the author opted out, which is the case
          # this exists to override.
          "steps" => [ { "id" => "s1", "tool" => "memory_stats", "params" => {} } ],
          "output" => {}
        }
      })
    end

    let(:permitted) do
      create(:user, account: account,
                    permissions: [ Ai::Tools::MemoryTool::REQUIRED_PERMISSION ])
    end

    def policy!(verdict)
      Ai::InterventionPolicy.register_category!("ai.recipe.memory_stats")
      Ai::InterventionPolicy.create!(
        account: account, action_category: "ai.recipe.memory_stats",
        scope: "global", policy: verdict, priority: 10, is_active: true
      )
    end

    it "pauses a step the author did not flag, when policy requires approval" do
      policy!("require_approval")

      run = described_class.execute(skill: plain_recipe, inputs: {},
                                    account: account, user: permitted, agent: nil)

      expect(run.status).to eq("paused_for_approval"),
                            "an operator policy did not override an author who omitted require_approval"
    end

    # THE OVER-FIRING CONTROL. With no policy row for this action the run must
    # complete exactly as before — default_policy's "require_approval" must NOT
    # leak in and pause everything.
    it "does not pause when no policy is configured for the step" do
      run = described_class.execute(skill: plain_recipe, inputs: {},
                                    account: account, user: permitted, agent: nil)

      expect(run.status).to eq("completed"),
                            "an unconfigured platform started pausing every recipe step: #{run.error_message}"
    end

    # A BLOCK is refused outright rather than paused. Pausing would offer an
    # approver the chance to release something the operator blocked, which is a
    # weaker verdict than the one they set.
    it "refuses a blocked step instead of offering it for approval" do
      policy!("block")

      run = described_class.execute(skill: plain_recipe, inputs: {},
                                    account: account, user: permitted, agent: nil)

      expect(run.status).to eq("failed"),
                            "a blocked step was paused rather than refused — an approver could release it"
      expect(run.error_message).to match(/blocked by operator policy/i)
    end

    # A permissive policy must not DISABLE an author-requested pause — friction
    # is one-way.
    it "does not let a permissive policy remove an author-requested approval" do
      policy!("auto_approve")
      flagged = create(:ai_skill, account: account, metadata: {
        "recipe" => {
          "version" => "1", "inputs" => [],
          "steps" => [ { "id" => "s1", "tool" => "memory_stats", "params" => {},
                         "require_approval" => true } ],
          "output" => {}
        }
      })

      run = described_class.execute(skill: flagged, inputs: {},
                                    account: account, user: permitted, agent: nil)

      expect(run.status).to eq("paused_for_approval")
    end
  end
end
