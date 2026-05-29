# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Missions::MissionComposer do
  let(:account) { create(:account) }
  let(:provider) { create(:ai_provider, provider_type: "openai") }
  let!(:agent) do
    create(:ai_agent, account: account, provider: provider, agent_type: "assistant", status: "active")
  end
  let(:intent) { "provision a node and deploy my app onto it" }

  subject(:composer) { described_class.new(account: account, intent: intent) }

  # Candidate contracts mirror the real provision_full_stack → deploy_app_code
  # I/O shapes (nested array output → scalar input via depends_on_outputs).
  let(:candidates) do
    [
      { skill: "provision_full_stack", slug: "system-provision-full-stack", description: "Provision a stack",
        inputs: { "template_id" => {}, "count" => {} },
        outputs: { "outputs" => { "node_instance_ids" => [] } } },
      { skill: "deploy_app_code", slug: "system-deploy-app-code", description: "Deploy code",
        inputs: { "node_instance_id" => {}, "repo_url" => {} },
        outputs: { "deployment_id" => nil } }
    ]
  end

  def stub_llm(steps)
    allow(composer).to receive(:candidate_skills).and_return(candidates)
    allow(composer).to receive(:call_llm).and_return(content: { steps: steps }.to_json)
  end

  describe "#compose!" do
    context "happy path — a provision → deploy DAG with cross-step data flow" do
      before do
        stub_llm([
          { step_number: 1, skill: "provision_full_stack", inputs: { "template_id" => "t1", "count" => 1 },
            dependencies: [], depends_on_outputs: {} },
          { step_number: 2, skill: "deploy_app_code", inputs: { "repo_url" => "https://example.com/app" },
            dependencies: [1],
            depends_on_outputs: { "node_instance_id" => { "from_step" => 1, "path" => "outputs.node_instance_ids", "select" => "first" } } }
        ])
      end

      it "persists a draft GoalPlan of skill-typed steps" do
        plan = composer.compose!

        expect(plan).to be_a(Ai::GoalPlan)
        expect(plan.status).to eq("draft")
        expect(plan.plan_data["composed_by"]).to eq("mission_composer")
        expect(plan.steps.count).to eq(2)
        expect(plan.steps.in_order.map { |s| s.execution_config["skill"] }).to eq(%w[provision_full_stack deploy_app_code])
        expect(plan.steps.in_order.map(&:step_type).uniq).to eq(["provisioning_skill"])
      end

      it "wires the downstream step's input from the upstream step's output" do
        plan = composer.compose!
        deploy = plan.steps.in_order.last

        expect(deploy.dependencies).to eq([1])
        expect(deploy.execution_config["depends_on_outputs"]["node_instance_id"]).to eq(
          "from_step" => 1, "path" => "outputs.node_instance_ids", "select" => "first"
        )
        expect(deploy.execution_config["on_failure"]).to eq("rollback")
      end
    end

    context "bound-skill guardrail — the LLM cannot invent skills" do
      before do
        stub_llm([
          { step_number: 1, skill: "provision_full_stack", inputs: {}, dependencies: [], depends_on_outputs: {} },
          { step_number: 2, skill: "totally_made_up_skill", inputs: {}, dependencies: [1], depends_on_outputs: {} }
        ])
      end

      it "drops steps referencing skills outside the candidate set" do
        plan = composer.compose!
        expect(plan.steps.count).to eq(1)
        expect(plan.steps.first.execution_config["skill"]).to eq("provision_full_stack")
      end
    end

    context "acyclic guardrail" do
      before do
        stub_llm([
          { step_number: 1, skill: "provision_full_stack", inputs: {}, dependencies: [2], depends_on_outputs: {} },
          { step_number: 2, skill: "deploy_app_code", inputs: {}, dependencies: [1], depends_on_outputs: {} }
        ])
      end

      it "rejects a cyclic DAG" do
        expect { composer.compose! }.to raise_error(described_class::CompositionError, /cycle/)
      end
    end

    context "cost-cap guardrail" do
      before do
        guard = double("CostCapGuardResult", cap_exceeded?: true, payload: { spent: 99, cap: 10 })
        allow(Ai::Provisioning::CostCapGuard).to receive(:allow?).with(account: account).and_return(guard)
      end

      it "returns nil and records the cap payload without calling the LLM" do
        expect(composer).not_to receive(:call_llm)
        expect(composer.compose!).to be_nil
        expect(composer.cap_exceeded_payload).to eq(spent: 99, cap: 10)
      end
    end

    context "empty intent" do
      subject(:composer) { described_class.new(account: account, intent: "   ") }

      it "raises" do
        expect { composer.compose! }.to raise_error(described_class::CompositionError, /intent is required/)
      end
    end
  end
end
