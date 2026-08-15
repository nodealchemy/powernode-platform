# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Tools::SelfImprovementTool do
  let(:account_a) { create(:account) }
  let(:account_b) { create(:account) }
  let(:agent) { create(:ai_agent, account: account_a) }

  # generate_self_challenge is gated on ai.manage (IMP-6fbfeff384fa) and the
  # per-action check fails closed for a principal it cannot ask, so an
  # agent-only tool is refused before dispatch. These examples are about
  # cross-account SKILL resolution, not authorization, so the caller is given
  # exactly the permission the action requires and the subject is unchanged.
  let(:caller_user) do
    create(:user, account: account_a, permissions: %w[ai.skills.read ai.manage])
  end
  let(:tool) { described_class.new(account: account_a, agent: agent, user: caller_user) }

  let(:service) { instance_double(Ai::SelfImprovement::ChallengeService) }
  let(:challenge) do
    create(:ai_self_challenge, account: account_a, challenger_agent: agent, executor_agent: agent)
  rescue StandardError
    # Fall back to a stub double if no factory exists — generate_self_challenge
    # only reads :id/:challenge_id/:status/:difficulty/:challenge_prompt for as_json.
    instance_double(Ai::SelfChallenge, as_json: { "id" => "x" })
  end

  before do
    allow(Ai::SelfImprovement::ChallengeService).to receive(:new).with(account: account_a).and_return(service)
  end

  # Params arrive via the registrar as with_indifferent_access — mirror that so
  # the spec drives the real param-access path (the tool reads params["skill_id"]).
  def run(action_params)
    tool.execute(params: action_params.with_indifferent_access)
  end

  describe "cross-account isolation (IDOR)" do
    it "does not resolve another account's skill — passes skill: nil to the service" do
      other_skill = create(:ai_skill, account: account_b)

      expect(service).to receive(:generate_challenge!)
        .with(hash_including(skill: nil))
        .and_return(challenge)

      result = run(action: "generate_self_challenge", skill_id: other_skill.id)
      expect(result[:success]).to be true
    end
  end

  describe "legitimate same-account access" do
    it "resolves the account's own skill and passes it to the service" do
      own_skill = create(:ai_skill, account: account_a)

      expect(service).to receive(:generate_challenge!)
        .with(hash_including(skill: own_skill))
        .and_return(challenge)

      result = run(action: "generate_self_challenge", skill_id: own_skill.id)
      expect(result[:success]).to be true
    end
  end
end
