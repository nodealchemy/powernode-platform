# frozen_string_literal: true

require "rails_helper"

# APO — the CHANNEL through which a project's SLO targets can arrive.
#
# The reader resolves a project's declared targets through the ladder, but
# until this verb there was no way to declare one: the only creation path
# passes account, name, status and creator, and the project surface had three
# read verbs and no write. Every project in existence carried empty targets, so
# even the two correctly-wired utilization ceilings had no channel.
#
# THE WRITE DOOR IS WHERE UNDECLARABLE BECOMES ENFORCEABLE. Latency has no
# producer anywhere on the platform; accepting a p99 target would store a
# number that resolves to nothing and read back as accepted. It is refused by
# name, with the reason.
#
# Every example asserts the stored ROW and the RESOLVED value, never a status.
RSpec.describe "Ai::Tools::ProjectTool project_set_slo_targets" do
  let(:account) { create(:account) }
  let(:user) do
    create(:user, account: account, permissions: %w[ai.missions.read ai.missions.manage])
  end
  let(:tool) { Ai::Tools::ProjectTool.new(account: account, user: user) }
  let!(:project) { create(:ai_project, account: account, name: "Ledger Service") }

  def set(**params)
    tool.execute(params: { action: "project_set_slo_targets", project_id: project.id, **params })
  end

  describe "registration" do
    it "is served from the registry and declared MUTATING" do
      expect(Ai::Tools::PlatformApiToolRegistry::TOOLS["project_set_slo_targets"])
        .to eq("Ai::Tools::ProjectTool")
      expect(Ai::Tools::ProjectTool.declared_action("project_set_slo_targets"))
        .to include(mutating: true)
    end
  end

  describe "declaring targets" do
    it "stores them on the project and resolves them through the mission ladder" do
      result = set(availability_pct: 99.9, cost_ceiling_usd: 500)

      expect(result[:success]).to be true
      expect(project.reload.slo_targets_hash)
        .to eq({ "availability_pct" => 99.9, "cost_ceiling_usd" => 500.0 })

      mission = create(:ai_mission, account: account, created_by: user,
                                    mission_type: "infrastructure", project: project)
      targets = mission.service_level_targets

      expect(targets.availability_pct).to eq(99.9)
      expect(targets.cost_ceiling_usd).to eq(500.0)
    end

    it "MERGES rather than replacing, so declaring one does not silently clear another" do
      set(availability_pct: 99.9)
      set(cost_ceiling_usd: 500)

      expect(project.reload.slo_targets_hash.keys).to contain_exactly("availability_pct", "cost_ceiling_usd")
    end

    it "clears one target with an explicit null and leaves the others" do
      set(availability_pct: 99.9, cost_ceiling_usd: 500)

      set(cost_ceiling_usd: nil)

      expect(project.reload.slo_targets_hash).to eq({ "availability_pct" => 99.9 })
    end

    it "accepts a cost far above 100 and a throughput floor in bytes per second" do
      set(cost_ceiling_usd: 25_000, min_throughput_bytes_per_s: 1_250_000)

      stored = project.reload.slo_targets_hash

      expect(stored["cost_ceiling_usd"]).to eq(25_000.0)
      expect(stored["min_throughput_bytes_per_s"]).to eq(1_250_000.0)
    end

    it "preserves the rest of configuration" do
      project.update!(configuration: { "watch_policies" => { "auto_scale_min_replicas" => 2 } })

      set(availability_pct: 99.0)

      expect(project.reload.configuration["watch_policies"]).to eq({ "auto_scale_min_replicas" => 2 })
    end

    it "returns what actually RESOLVES, not merely what was sent" do
      # A caller has to be able to tell a declaration that took effect from one
      # a narrower rung shadows.
      result = set(availability_pct: 99.9)

      expect(result[:data][:slo_targets]["availability_pct"]).to eq(99.9)
      expect(result[:data][:undeclarable]).to include("p99_latency_ms")
    end
  end

  describe "refusals" do
    it "REFUSES a latency target by name, with the reason" do
      result = set(p99_latency_ms: 250)

      expect(result[:success]).to be false
      expect(result[:error]).to match(/p99_latency_ms/)
      expect(result[:error]).to match(/no producer/i)
      expect(project.reload.slo_targets_hash).to eq({})
    end

    it "REFUSES an unusable percentage rather than storing a value that resolves to nothing" do
      result = set(availability_pct: 140)

      expect(result[:success]).to be false
      expect(result[:error]).to match(/availability_pct/)
      expect(project.reload.slo_targets_hash).to eq({})
    end

    it "REFUSES a non-positive cost ceiling" do
      result = set(cost_ceiling_usd: 0)

      expect(result[:success]).to be false
      expect(project.reload.slo_targets_hash).to eq({})
    end

    it "REFUSES a call that names no target at all" do
      result = set

      expect(result[:success]).to be false
      expect(result[:error]).to match(/at least one/i)
    end

    it "REFUSES a project in another account, and leaves its row untouched" do
      foreign = create(:ai_project, account: create(:account))

      result = tool.execute(params: { action: "project_set_slo_targets",
                                      project_id: foreign.id, availability_pct: 99.0 })

      expect(result[:success]).to be false
      expect(foreign.reload.slo_targets_hash).to eq({})
    end

    it "REFUSES a caller holding only the read permission" do
      reader = create(:user, account: account, permissions: %w[ai.missions.read])
      read_only = Ai::Tools::ProjectTool.new(account: account, user: reader)

      result = read_only.execute(params: { action: "project_set_slo_targets",
                                           project_id: project.id, availability_pct: 99.0 })

      expect(result[:success]).to be false
      expect(result[:error]).to match(/permission/i)
      expect(project.reload.slo_targets_hash).to eq({})
    end

    it "still lets that reader READ" do
      reader = create(:user, account: account, permissions: %w[ai.missions.read])
      read_only = Ai::Tools::ProjectTool.new(account: account, user: reader)

      expect(read_only.execute(params: { action: "project_list" })[:success]).to be true
    end
  end
end
