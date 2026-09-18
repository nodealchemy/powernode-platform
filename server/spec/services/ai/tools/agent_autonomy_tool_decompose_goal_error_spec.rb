# frozen_string_literal: true

require "rails_helper"

# IMP-f80736b11ac1 — decompose_goal's StandardError rescue used to echo a raw
# exception message straight into the tool result sent to the model provider,
# and logged nothing server-side — so the detail leaked outward and was lost
# inward in the same rescue. Both arms are asserted as SEPARATE examples: a
# change that only sanitizes the provider-facing string but logs nothing would
# still pass a combined assertion.
RSpec.describe "agent_autonomy MCP decompose_goal: sanitized provider errors" do
  let(:account) { create(:account) }
  let!(:actor) { create(:user, account: account, permissions: %w[ai.agents.read ai.goals.manage]) }
  let(:agent) { create(:ai_agent, account: account) }
  let!(:goal) do
    account.ai_agent_goals.create!(
      agent: agent, title: "probe goal", goal_type: "improvement", status: "active", priority: 3
    )
  end
  let(:leak) { /PG::|UniqueViolation|duplicate key|constraint|idx_probe/i }

  def run
    ::Ai::Tools::McpPlatformToolRegistrar.execute_tool(
      "platform.decompose_goal",
      params: { "goal_id" => goal.id },
      account: account,
      user: actor
    )
  end

  before do
    # stub_const, not allow(...).to receive(:new): GoalDecompositionService's
    # real #initialize only accepts account: (a separate, unrelated defect —
    # the call site at :828 also passes agent:), and rspec-mocks' verifying
    # partial double ALWAYS checks a stubbed .new's call args against the
    # real #initialize signature (unconditionally — without_partial_double_
    # verification does not cover it; see VerifyingExistingMethodDouble.for
    # in rspec-mocks), so that extra agent: keyword raises ArgumentError from
    # RSpec's own verification before and_raise ever fires. Replacing the
    # constant with a fake class sidesteps verification entirely (nothing is
    # stubbed on the real object) and exercises the rescue StandardError arm
    # directly, so this spec stays correct if the constructor mismatch is
    # ever fixed independently.
    fake_service_class = Class.new do
      def self.new(*, **)
        raise ActiveRecord::StatementInvalid,
          'PG::UniqueViolation: ERROR: duplicate key value violates unique constraint "idx_probe"'
      end
    end
    stub_const("Ai::Autonomy::GoalDecompositionService", fake_service_class)
    allow(Rails.logger).to receive(:error).and_call_original
  end

  it "keeps the raised error's class and driver text out of the provider-facing result" do
    result = run

    expect(result).to include(success: false, error: "Goal decomposition failed")
    expect(result.to_s).not_to match(leak)
  end

  it "logs the raised error's class and driver text server-side" do
    run

    expect(Rails.logger).to have_received(:error)
      .with(/decompose_goal failed: ActiveRecord::StatementInvalid: PG::UniqueViolation/)
  end

  # NameError is NoMethodError's superclass, so a NoMethodError raised anywhere
  # in decompose_goal's body — not just a genuinely missing constant — lands in
  # the `rescue NameError` arm above the StandardError one this file otherwise
  # exercises. That arm already returned a stable provider message before this
  # change; what it did NOT do was log, so a NoMethodError there was recorded
  # nowhere at all. Own context: a distinct stub_const, since this needs the
  # constructor to succeed and the failure to come from #decompose instead.
  context "when the failure is a NoMethodError (NameError's subclass, not caught by rescue StandardError)" do
    before do
      fake_service_class = Class.new do
        def self.new(*, **)
          allocate
        end

        def decompose(**)
          raise NoMethodError, "undefined method 'frobnicate_the_plan' for #<Ai::Autonomy::GoalDecompositionService>"
        end
      end
      stub_const("Ai::Autonomy::GoalDecompositionService", fake_service_class)
      allow(Rails.logger).to receive(:error).and_call_original
    end

    it "logs the NoMethodError's class and driver text server-side" do
      run

      expect(Rails.logger).to have_received(:error)
        .with(/decompose_goal unavailable: NoMethodError: undefined method 'frobnicate_the_plan'/)
    end

    # Regression guard, not a reproduction: this arm never leaked — it already
    # returned the stable message before this change, it just never logged.
    # Asserted as its own example (mirroring :54) so a future edit to this
    # rescue arm that starts interpolating e.message into the provider-facing
    # string (plausible: the DOA fix in 01a0b454 touches this same method)
    # reddens here even though the log assertion above would stay green.
    it "keeps the provider-facing result stable and free of the raised error's driver text" do
      result = run

      expect(result).to include(success: false, error: "Goal decomposition service not available")
      expect(result.to_s).not_to match(leak)
    end
  end
end
