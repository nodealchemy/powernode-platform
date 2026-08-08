# frozen_string_literal: true

require "rails_helper"

# Multi-region placement distribution (IMP 019fe351-7d10).
#
# resolve_region_for_brief returned Array(brief["regions"]).first and
# merge_resolved_inputs! stamped that single provider_region_id onto the step
# along with the FULL instance count. A brief asking for ['dna','rna'] with
# scale.initial 3 produced 3 instances on dna and nothing on rna — the
# operator's stated multi-region intent silently dropped. Observed live
# 2026-08-08 on plan 019fe1db-f680-7116-8e76-110166f070ed.
#
# Distribution is safe from the step merger: #mergeable? only collapses steps
# agreeing on template_id AND provider_region_id AND provider_instance_type_id,
# so per-region siblings are left alone. SkillCompositionRunner executes steps
# in topological layers, so N provisioning steps is an ordinary shape.
#
# Implementation note the specs pin: siblings are APPENDED (numbered after every
# existing step) rather than inserted, and anything that depended on the original
# step gains a dependency on each sibling. That keeps the DAG correct without
# renumbering — inserting-and-shifting is what makes merge_step_pair! hairy, and
# there is no reason to take that on here.
RSpec.describe Ai::Provisioning::PlanComposerService, "multi-region placement", type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:mission) { create(:ai_mission, account: account, created_by: user, mission_type: "infrastructure") }
  subject(:service) { described_class.new(account: account, mission: mission) }

  before do
    skip "system extension not loaded" unless defined?(::System::ProviderRegion)
    ::System::ProviderRegion.where(account_id: account.id).destroy_all
    ::System::Provider.where(account_id: account.id).destroy_all
  end

  let(:sys_provider) do
    ::System::Provider.create!(account: account, name: "IPNode PVE", provider_type: "proxmox", enabled: true)
  end
  let!(:dna) do
    ::System::ProviderRegion.create!(account: account, provider: sys_provider,
                                     region_code: "dna", name: "dna", enabled: true)
  end
  let!(:rna) do
    ::System::ProviderRegion.create!(account: account, provider: sys_provider,
                                     region_code: "rna", name: "rna", enabled: true)
  end

  def brief_for(regions, count)
    { "regions" => regions, "scale" => { "initial" => count, "target" => count } }
  end

  describe "#resolve_regions_for_brief" do
    it "resolves every named region, in brief order" do
      expect(service.send(:resolve_regions_for_brief, brief_for(%w[dna rna], 2))).to eq([dna, rna])
    end

    it "resolves by region_code as well as name" do
      expect(service.send(:resolve_regions_for_brief, brief_for(%w[rna dna], 2))).to eq([rna, dna])
    end

    it "de-duplicates when two names resolve to the same region" do
      expect(service.send(:resolve_regions_for_brief, brief_for(%w[dna dna], 2))).to eq([dna])
    end

    it "skips names that resolve to nothing rather than substituting" do
      # 'fna' has no region record here; it must not silently become dna.
      allow(Rails.logger).to receive(:warn)
      expect(service.send(:resolve_regions_for_brief, brief_for(%w[dna fna], 2))).to eq([dna])
    end

    it "returns [] for a brief naming no regions" do
      expect(service.send(:resolve_regions_for_brief, brief_for([], 2))).to eq([])
    end
  end

  describe "#split_count_across" do
    it "splits evenly when it divides" do
      expect(service.send(:split_count_across, 4, 2)).to eq([2, 2])
    end

    it "gives the remainder to the earliest regions" do
      expect(service.send(:split_count_across, 3, 2)).to eq([2, 1])
      expect(service.send(:split_count_across, 5, 3)).to eq([2, 2, 1])
    end

    it "never emits a zero share — fewer instances than regions means fewer steps" do
      expect(service.send(:split_count_across, 1, 3)).to eq([1])
      expect(service.send(:split_count_across, 2, 3)).to eq([1, 1])
    end

    it "preserves the total" do
      [[7, 3], [3, 2], [10, 4], [1, 1]].each do |total, n|
        expect(service.send(:split_count_across, total, n).sum).to eq(total)
      end
    end
  end

  describe "#fan_out_regions! (the distribution pass)" do
    let(:agent) { create(:ai_agent, account: account, creator: user, status: "active") }
    let(:goal) do
      Ai::AgentGoal.create!(
        account: account, agent: agent, title: "Goal", goal_type: "creation",
        status: "pending", priority: 3, progress: 0.0, success_criteria: {}
      )
    end
    let(:plan) do
      Ai::GoalPlan.create!(account: account, goal: goal, agent: agent,
                           status: "draft", version: 1, plan_data: {})
    end

    def provision_step!(number, count, region_id, deps = [])
      plan.steps.create!(
        step_number: number, step_type: "provisioning_skill", description: "provision",
        dependencies: deps,
        execution_config: { "skill" => "provision_full_stack", "on_failure" => "rollback",
                            "inputs" => { "count" => count, "provider_region_id" => region_id,
                                          "template_id" => "tmpl-1", "provider_instance_type_id" => "it-1" } }
      )
    end

    def other_step!(number, deps)
      plan.steps.create!(
        step_number: number, step_type: "provisioning_skill", description: "docker",
        dependencies: deps,
        execution_config: { "skill" => "docker_provision", "inputs" => {}, "on_failure" => "rollback" }
      )
    end

    it "splits one provisioning step into one per region, preserving the total count" do
      provision_step!(1, 3, dna.id)
      service.send(:fan_out_regions!, plan, brief_for(%w[dna rna], 3))

      pf = plan.steps.reload.select { |s| s.execution_config["skill"] == "provision_full_stack" }
      expect(pf.size).to eq(2)
      expect(pf.sum { |s| s.execution_config["inputs"]["count"].to_i }).to eq(3)
      expect(pf.map { |s| s.execution_config["inputs"]["provider_region_id"] }).to match_array([dna.id, rna.id])
    end

    it "gives the remainder to the earliest region" do
      provision_step!(1, 3, dna.id)
      service.send(:fan_out_regions!, plan, brief_for(%w[dna rna], 3))
      by_region = plan.steps.reload.each_with_object({}) do |s, h|
        next unless s.execution_config["skill"] == "provision_full_stack"
        h[s.execution_config["inputs"]["provider_region_id"]] = s.execution_config["inputs"]["count"].to_i
      end
      expect(by_region[dna.id]).to eq(2)
      expect(by_region[rna.id]).to eq(1)
    end

    it "carries the siblings' other inputs over unchanged" do
      provision_step!(1, 2, dna.id)
      service.send(:fan_out_regions!, plan, brief_for(%w[dna rna], 2))
      sib = plan.steps.reload.find { |s| s.execution_config.dig("inputs", "provider_region_id") == rna.id }
      expect(sib.execution_config["inputs"]["template_id"]).to eq("tmpl-1")
      expect(sib.execution_config["inputs"]["provider_instance_type_id"]).to eq("it-1")
      expect(sib.execution_config["skill"]).to eq("provision_full_stack")
      expect(sib.execution_config["on_failure"]).to eq("rollback")
    end

    it "makes dependents wait for EVERY sibling, not just the original" do
      provision_step!(1, 2, dna.id)
      other_step!(2, [1])
      service.send(:fan_out_regions!, plan, brief_for(%w[dna rna], 2))

      dependent = plan.steps.reload.find { |s| s.execution_config["skill"] == "docker_provision" }
      sibling = plan.steps.reload.find { |s| s.execution_config.dig("inputs", "provider_region_id") == rna.id }
      expect(dependent.dependencies.map(&:to_i)).to include(1, sibling.step_number)
    end

    it "appends siblings after every existing step rather than renumbering" do
      provision_step!(1, 2, dna.id)
      other_step!(2, [1])
      service.send(:fan_out_regions!, plan, brief_for(%w[dna rna], 2))

      sibling = plan.steps.reload.find { |s| s.execution_config.dig("inputs", "provider_region_id") == rna.id }
      expect(sibling.step_number).to be > 2
      # untouched steps keep their original numbers
      expect(plan.steps.reload.find { |s| s.execution_config["skill"] == "docker_provision" }.step_number).to eq(2)
    end

    it "is a no-op for a single-region brief" do
      provision_step!(1, 3, dna.id)
      expect { service.send(:fan_out_regions!, plan, brief_for(%w[dna], 3)) }
        .not_to change { plan.steps.reload.count }
    end

    it "is a no-op when the brief names no regions" do
      provision_step!(1, 3, dna.id)
      expect { service.send(:fan_out_regions!, plan, brief_for([], 3)) }
        .not_to change { plan.steps.reload.count }
    end

    it "creates fewer steps than regions when there are fewer instances" do
      provision_step!(1, 1, dna.id)
      service.send(:fan_out_regions!, plan, brief_for(%w[dna rna], 1))
      pf = plan.steps.reload.select { |s| s.execution_config["skill"] == "provision_full_stack" }
      expect(pf.size).to eq(1)
      expect(pf.first.execution_config["inputs"]["count"].to_i).to eq(1)
    end

    it "leaves non-provisioning steps alone" do
      other_step!(1, [])
      expect { service.send(:fan_out_regions!, plan, brief_for(%w[dna rna], 3)) }
        .not_to change { plan.steps.reload.count }
    end
  end
end
