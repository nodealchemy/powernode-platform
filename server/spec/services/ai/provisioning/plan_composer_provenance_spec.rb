# frozen_string_literal: true

require "rails_helper"

# F3 (IMP 019fe4c4-e813): the charter makes the dryrun- prefix the
# blast-radius boundary, yet mission-provisioned VMs came out named
# powernode-ops-cell-N-<hex> — the mission's marker never reached instance
# naming, so prefix-targeted teardown/audit missed every artifact and cleanup
# fell back to hand-collected instance ids (all four runs).
#
# The composer now threads naming provenance into provision step inputs:
#   name_prefix — explicit configuration.name_prefix, else derived from
#                 configuration.dryrun_run_id ("dryrun-<runId>"), else absent
#   mission_id  — always, so created nodes/instances are provenance-queryable
RSpec.describe Ai::Provisioning::PlanComposerService, "naming provenance", type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  def mission_with(configuration)
    create(:ai_mission, account: account, created_by: user, mission_type: "infrastructure",
                        configuration: configuration)
  end

  def resolved_inputs(mission)
    service = described_class.new(account: account, mission: mission)
    inputs = {}
    service.send(:merge_resolved_inputs!, inputs, { "scale" => { "initial" => 1 } }, "provision_full_stack")
    inputs
  end

  it "derives name_prefix from dryrun_run_id and stamps mission_id" do
    mission = mission_with({ "dryrun" => true, "dryrun_run_id" => "20260809d" })
    inputs = resolved_inputs(mission)

    expect(inputs["name_prefix"]).to eq("dryrun-20260809d")
    expect(inputs["mission_id"]).to eq(mission.id)
  end

  it "prefers an explicit configuration.name_prefix" do
    mission = mission_with({ "name_prefix" => "canary", "dryrun_run_id" => "x" })
    expect(resolved_inputs(mission)["name_prefix"]).to eq("canary")
  end

  it "stamps mission_id but no prefix when neither marker is configured" do
    mission = mission_with({})
    inputs = resolved_inputs(mission)

    expect(inputs).not_to have_key("name_prefix")
    expect(inputs["mission_id"]).to eq(mission.id)
  end

  it "never overrides a caller-provided name_prefix input" do
    mission = mission_with({ "dryrun_run_id" => "z" })
    service = described_class.new(account: account, mission: mission)
    inputs = { "name_prefix" => "explicit" }
    service.send(:merge_resolved_inputs!, inputs, { "scale" => { "initial" => 1 } }, "provision_full_stack")
    expect(inputs["name_prefix"]).to eq("explicit")
  end
end
