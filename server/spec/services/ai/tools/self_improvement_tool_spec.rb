# frozen_string_literal: true

require "rails_helper"

# CROSS-ACCOUNT SKILL RESOLUTION (IDOR) on Ai::Tools::SelfImprovementTool.
#
# This file used to drive the property through `generate_self_challenge`, whose
# skill lookup was the tool's first account-scoped `find_by`. Increment D6
# deleted that verb with the rest of the self-challenge subsystem, and the
# property did NOT go with it: `mutate_skill` resolves a caller-supplied
# skill_id exactly the same way, and it WRITES — it rewrites the skill's prompt
# as a new version.
#
# So the subject moved rather than the oracle disappearing. Deleting the file
# with its verb would have quietly retired a security assertion whose subject
# was still there under a different name.
#
# `mutate_skill` is approval-gated (dev.prompt_refine, HIER-P2B-ENG), so the
# scoping check runs in TWO places that must agree: the action body, and
# #mutate_skill_gate_context, which resolves the target BEFORE parking so a
# foreign skill never becomes a pending approval an operator has to dispose of.
# Both are asserted.
RSpec.describe Ai::Tools::SelfImprovementTool do
  let(:account_a) { create(:account) }
  let(:account_b) { create(:account) }
  let(:agent) { create(:ai_agent, account: account_a) }

  # The per-action check fails closed for a principal it cannot ask, so the
  # caller is given exactly the permission mutate_skill requires
  # (ai.skills.update) on top of the class floor. These examples are about
  # cross-account resolution, not authorization.
  let(:caller_user) do
    create(:user, account: account_a, permissions: %w[ai.skills.read ai.skills.update])
  end
  let(:tool) { described_class.new(account: account_a, agent: agent, user: caller_user) }

  let(:service) { instance_double(Ai::SelfImprovement::SkillMutationService) }

  before do
    allow(Ai::SelfImprovement::SkillMutationService).to receive(:new)
      .with(account: account_a).and_return(service)
  end

  # Params arrive via the registrar as with_indifferent_access — mirror that so
  # the spec drives the real param-access path.
  def run(action_params)
    tool.execute(params: action_params.with_indifferent_access)
  end

  describe "cross-account isolation (IDOR)" do
    it "refuses another account's skill instead of mutating it" do
      other_skill = create(:ai_skill, account: account_b)
      expect(service).not_to receive(:mutate!)

      result = run(action: "mutate_skill", skill_id: other_skill.id, strategy: "learning_driven")

      expect(result[:success]).to be false
      expect(result[:error]).to match(/Skill not found/)
    end

    # The gate context runs BEFORE Ai::AutonomyGate parks anything, so a
    # foreign skill must be refused there too rather than becoming an approval
    # request naming a resource the caller cannot reach.
    it "refuses another account's skill in the gate context, before parking" do
      other_skill = create(:ai_skill, account: account_b)

      expect {
        tool.send(:mutate_skill_gate_context,
                  { "skill_id" => other_skill.id, "strategy" => "learning_driven" }.with_indifferent_access)
      }.to raise_error(ArgumentError, /Skill not found/)
    end
  end

  describe "legitimate same-account access" do
    # The CONTROL for the two refusals above. mutate_skill is approval-gated
    # (dev.prompt_refine), so a permitted call on the account's OWN skill does
    # not return a version — it parks a deferred operation and returns the
    # pending envelope. That is the correct evidence that the call got past
    # both the permission check and the gate context: a foreign skill never
    # reaches this point, because #mutate_skill_gate_context raises first.
    it "parks an approval for the account's own skill instead of refusing it" do
      own_skill = create(:ai_skill, account: account_a)
      expect(service).not_to receive(:mutate!)

      result = run(action: "mutate_skill", skill_id: own_skill.id, strategy: "learning_driven")

      expect(result[:success]).to be true
      expect(result[:data][:pending]).to be true
      expect(result[:data][:action_category]).to eq("dev.prompt_refine")
      expect(result[:data][:approval_request_id]).to be_present
    end
  end

  # D6 deleted three verbs. Asserted here, on the tool itself, so the class
  # cannot regrow them: an action that is declared but unrouted, or routed but
  # undeclared, is the shape the registry-completeness specs exist to catch and
  # this is the local, readable statement of the same fact.
  describe "the deleted self-challenge verbs" do
    %w[generate_self_challenge list_challenges get_challenge_result].each do |action|
      it "no longer advertises or declares #{action}" do
        expect(described_class.action_definitions).not_to have_key(action)
        expect(described_class.declared_actions).not_to have_key(action)
        expect(described_class::ACTION_PERMISSIONS).not_to have_key(action)
      end
    end

    it "refuses one as an unknown action rather than dispatching it" do
      result = run(action: "generate_self_challenge", skill_id: "anything")

      expect(result[:success]).to be false
      expect(result[:error]).to match(/Unknown action/)
    end

    # The other arm: the three surviving actions are all still there, so an
    # over-eager deletion cannot pass the examples above.
    it "still advertises the three skill verbs" do
      expect(described_class.action_definitions.keys)
        .to match_array(%w[mutate_skill compose_skills auto_evolve_skill])
    end
  end
end
