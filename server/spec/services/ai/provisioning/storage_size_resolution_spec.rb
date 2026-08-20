# frozen_string_literal: true

require "rails_helper"

# IMP-b439270dab0d — one storage-size resolution order, four readers.
#
# The order was spelled four times with three different answers:
#
#   ProvisionFullStackExecutor.resolve_storage_gb   with_storage_gb, storage_gb — present?
#   CostEstimatorService#declared_gb                same order, same present?
#   PlanSnapshotService (x2, display)               TRUTHINESS, and a third key
#   PlanComposerService                             never reads the STEP's alias
#
# TWO RULINGS, both settled from evidence rather than preference — see the
# commit message:
#
#   size_gb is NOT an alias. Every `size_gb` in the tree is
#   ProviderVolume#size_gb, the volume model's own column — a different noun.
#   Nothing writes it as a step input, and neither the published reader nor the
#   estimator reads it, so exactly one display path honoured a key no producer
#   emits. It is removed rather than promoted.
#
#   A step's OWN declaration outranks the brief. plan_composer_service says so
#   in prose ("an explicitly-authored input ... must always win") and the code
#   disagreed through the alias: a step carrying storage_gb: 500 had
#   with_storage_gb stamped from the brief, and the published order then let the
#   brief's value beat the step's own explicit one.
RSpec.describe Shared::StorageSizeResolution do
  describe ".from_inputs" do
    it "prefers the advertised key" do
      expect(described_class.from_inputs("with_storage_gb" => 25, "storage_gb" => 50)).to eq(25)
    end

    it "falls through to the alias" do
      expect(described_class.from_inputs("storage_gb" => 50)).to eq(50)
    end

    # present?, not truthiness: a blank-but-non-nil advertised value must not
    # beat a real alias. This is the snapshot service's divergence.
    it "falls through a blank advertised value to the alias" do
      expect(described_class.from_inputs("with_storage_gb" => "", "storage_gb" => 50)).to eq(50)
    end

    # An explicit 0 is a legitimate "no storage" answer, not an absent one.
    it "keeps an explicit zero" do
      expect(described_class.from_inputs("with_storage_gb" => 0, "storage_gb" => 50)).to eq(0)
    end

    it "tolerates symbol keys" do
      expect(described_class.from_inputs(storage_gb: 50)).to eq(50)
    end

    it "does not read size_gb — that is ProviderVolume's column, not a step input" do
      expect(described_class.from_inputs("size_gb" => 50)).to be_nil
    end
  end

  # The point of a published reader is that the other surfaces AGREE with it.
  # Asserted against each real reader rather than against a restatement here,
  # so a future change to the order moves them together or fails.
  describe "every surface agrees" do
    let(:account) { create(:account) }

    inputs_matrix = [
      { "with_storage_gb" => 25, "storage_gb" => 50 },
      { "storage_gb" => 50 },
      { "with_storage_gb" => "", "storage_gb" => 50 },
      { "with_storage_gb" => 0, "storage_gb" => 50 },
      { "size_gb" => 50 }
    ]

    inputs_matrix.each do |inputs|
      it "resolves #{inputs.inspect} identically in the executor and the snapshot label" do
        canonical = described_class.from_inputs(inputs).to_i

        if defined?(::System::Ai::Skills::ProvisionFullStackExecutor)
          executor = ::System::Ai::Skills::ProvisionFullStackExecutor.resolve_storage_gb(
            inputs["with_storage_gb"], inputs["storage_gb"]
          )
          expect(executor.to_i).to eq(canonical), "the published reader disagrees"
        end

        label = Ai::Provisioning::PlanSnapshotService
                .new(account: account)
                .send(:derive_step_name, "attach_storage", inputs)
        expected = canonical.positive? ? "Attach #{canonical}GB volume" : "Attach storage"
        expect(label).to eq(expected), "the snapshot label disagrees"
      end
    end
  end
end

# RULING 2 — a step's own declaration outranks the brief.
#
# plan_composer_service states the intent in prose: "an explicitly-authored
# input (a hand-written plan_data, MissionComposer output, an operator-supplied
# value) must always win". The code disagreed THROUGH THE ALIAS: it stamped
# with_storage_gb from the brief without ever consulting the step's own
# storage_gb, and the published order then let the brief's value beat the step's
# explicit one.
RSpec.describe Ai::Provisioning::PlanComposerService, "storage declared on the step" do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:ai_provider) { create(:ai_provider, account: account, is_active: true) }
  let!(:agent) do
    create(:ai_agent, account: account, provider: ai_provider, creator: user, status: "active")
  end

  let(:brief) do
    { "intent" => "provision a stack", "use_case" => "validation",
      "scale" => { "initial" => 1, "target" => 1 }, "regions" => [],
      "storage_gb" => 100 }
  end
  let(:mission) do
    create(:ai_mission, account: account, created_by: user, mission_type: "infrastructure",
                        configuration: { "brief" => brief })
  end

  subject(:service) { described_class.new(account: account, mission: mission) }

  def rewritten_inputs(step_inputs)
    goal = Ai::AgentGoal.create!(
      account: account, agent: agent, title: "g", description: "t",
      goal_type: "creation", status: "pending", priority: 3, progress: 0.0
    )
    plan = Ai::GoalPlan.create!(account: account, goal: goal, agent: agent, status: "draft", version: 1)
    step = Ai::GoalPlanStep.create!(
      plan: plan, step_number: 1, step_type: "provisioning_skill", status: "pending",
      dependencies: [],
      execution_config: { "skill" => "provision_full_stack", "inputs" => step_inputs }
    )
    service.send(:rewrite_step!, step, brief)
    step.reload.execution_config["inputs"]
  end

  it "keeps the step's own alias rather than stamping the brief over it" do
    inputs = rewritten_inputs("storage_gb" => 500)

    expect(inputs["with_storage_gb"]).to eq(500),
                                         "the brief overrode the step's own explicit declaration"
  end

  it "still falls back to the brief when the step declares nothing" do
    inputs = rewritten_inputs({})

    expect(inputs["with_storage_gb"]).to eq(100)
  end

  # An explicit 0 on the step is a legitimate "no storage" and must not be
  # replaced by the brief's positive value.
  it "lets an explicit zero on the step beat the brief" do
    inputs = rewritten_inputs("with_storage_gb" => 0)

    expect(inputs["with_storage_gb"]).to eq(0)
  end
end
