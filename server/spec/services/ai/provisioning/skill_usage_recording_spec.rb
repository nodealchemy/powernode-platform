# frozen_string_literal: true

require "rails_helper"

# F5 (IMP 019fe4c5-19a8): protocol §3's skill-utilization oracle reads
# ai_skill_usage_records, which only Ai::McpAgentExecutor wrote — the mission
# path's step executors bypassed it entirely, so every dry-run graded the
# skills dimension NO ORACLE despite executing provisioning skills. The
# runner is the mission path's execution seam; it records usage there.
RSpec.describe Ai::Provisioning::SkillCompositionRunner, "skill usage recording", type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:mission) do
    create(:ai_mission, account: account, created_by: user, mission_type: "infrastructure",
                        status: "active", current_phase: "execute",
                        custom_phases: [ { "key" => "execute", "label" => "Execute", "order" => 0 } ])
  end
  let(:agent) { create(:ai_agent, account: account, creator: user, status: "active") }
  let(:goal) do
    Ai::AgentGoal.create!(account: account, agent: agent, title: "G", goal_type: "creation",
                          status: "pending", priority: 3, progress: 0.0, success_criteria: {})
  end
  let(:plan) do
    Ai::GoalPlan.create!(account: account, goal: goal, agent: agent,
                         status: "executing", version: 1, plan_data: {})
  end
  let!(:step) do
    plan.steps.create!(
      step_number: 1, step_type: "provisioning_skill", description: "provision",
      status: "pending",
      execution_config: { "skill" => "provision_full_stack", "inputs" => {}, "on_failure" => "continue" }
    )
  end
  let!(:skill) { create(:ai_skill, account: account, name: "provision_full_stack") }

  let(:fake_executor_class) do
    Class.new do
      class << self
        attr_accessor :execute_result
      end
      def self.descriptor = { name: "provision_full_stack" }
      def initialize(account: nil); end

      def execute(**)
        self.class.execute_result
      end
    end
  end

  subject(:runner) { described_class.new(account: account, mission: mission, plan: plan) }

  before do
    allow(MissionChannel).to receive(:broadcast_mission_event)
    allow(WorkerJobService).to receive(:enqueue_job)
    allow(runner).to receive(:resolve_executor).with("provision_full_stack").and_return(fake_executor_class)
    allow(runner).to receive(:advance_mission_if_dag_complete!)
    runner.execute!
  end

  it "records a success usage row with duration and mission provenance" do
    fake_executor_class.execute_result = { success: true, data: {} }

    expect { runner.execute_step!(step) }.to change(Ai::SkillUsageRecord, :count).by(1)

    record = Ai::SkillUsageRecord.last
    expect(record.ai_skill_id).to eq(skill.id)
    expect(record.account_id).to eq(account.id)
    expect(record.outcome).to eq("success")
    expect(record.duration_ms).to be_a(Integer)
    expect(record.execution_type).to eq("provisioning_step")
    expect(record.metadata["mission_id"]).to eq(mission.id)
    expect(record.metadata["step_number"]).to eq(1)
  end

  it "records a failure usage row when the executor fails" do
    fake_executor_class.execute_result = { success: false, error: "boom" }

    expect { runner.execute_step!(step) }.to change(Ai::SkillUsageRecord, :count).by(1)
    expect(Ai::SkillUsageRecord.last.outcome).to eq("failure")
  end

  it "never lets recording break the step when no Ai::Skill row matches" do
    skill.destroy!
    fake_executor_class.execute_result = { success: true, data: {} }

    result = nil
    expect { result = runner.execute_step!(step) }.not_to change(Ai::SkillUsageRecord, :count)
    expect(result[:success]).to be true
  end
end
