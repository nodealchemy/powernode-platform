# frozen_string_literal: true

require "rails_helper"

# APO — the FOUR remaining SLO targets get the same ladder the ceilings have.
#
# APO-3a gave a project's scaling window one home and one walk, and
# IMP-7684d3f8658a did the same for the cpu / memory ceilings. Availability, the
# cost ceiling and the throughput floor were left read straight off
# `mission.configuration["slo_targets"]` by the consumer, so a project that
# declared any of them was silently unobserved: the declaration landed in a row
# nothing on the evaluation path ever looked at.
#
# THE FIX IS A READER, NOT A SECOND LOOKUP. The consumer must not read the
# project itself — that would make two readers of one project's targets, which
# is exactly what the single-ladder design exists to prevent, and they would be
# free to disagree about the same project.
#
# LATENCY IS EXCLUDED BY DESIGN AND SAYS SO. It has no producer anywhere on the
# platform, its intended transport was ruled dormant, the adapter says not to
# revive it and a guard fails if an emitter reappears. It is returned as an
# explicit `undeclarable` entry rather than as a blank, because a blank invites
# the next reader to treat it as a gap to fill — and the nearest thing to reach
# for measures the control plane's own components, not a workload.
RSpec.describe "Ai::Mission#service_level_targets" do
  let(:account) { create(:account) }
  let(:user)    { create(:user, account: account) }

  let(:mission_slo)  { {} }
  let(:mission_brief) { {} }
  let(:project_slo)  { {} }
  let(:template_slo) { {} }

  let(:project) do
    create(:ai_project, account: account, configuration: { "slo_targets" => project_slo })
  end

  let(:mission_template) do
    create(:ai_mission_template, account: account,
                                 default_configuration: { "slo_targets" => template_slo })
  end

  def build_mission(with_project: true)
    create(:ai_mission,
           account: account, created_by: user, mission_type: "infrastructure",
           mission_template: mission_template,
           project: with_project ? project : nil,
           configuration: { "slo_targets" => mission_slo, "brief" => mission_brief })
  end

  let(:mission) { build_mission }

  describe "availability_pct" do
    context "when only the PROJECT declares it" do
      let(:project_slo) { { "availability_pct" => 99.9 } }

      it "resolves off the project" do
        expect(mission.service_level_targets.availability_pct).to eq(99.9)
      end
    end

    context "when the MISSION declares it too" do
      let(:project_slo) { { "availability_pct" => 99.9 } }
      let(:mission_slo) { { "availability_pct" => 95.0 } }

      it "keeps the mission's own declaration decisive" do
        expect(mission.service_level_targets.availability_pct).to eq(95.0)
      end
    end

    context "when the TEMPLATE declares it" do
      let(:template_slo) { { "availability_pct" => 90.0 } }
      let(:project_slo)  { { "availability_pct" => 99.99 } }

      it "puts the project ABOVE the template" do
        expect(mission.service_level_targets.availability_pct).to eq(99.99)
      end
    end

    it "is nil when nothing declares it, so the consumer keeps owning its own default" do
      # The reader states what was DECLARED. Substituting a platform default
      # here would make "nobody said" indistinguishable from "somebody said
      # exactly the default".
      expect(mission.service_level_targets.availability_pct).to be_nil
    end

    context "when a declaration is not a usable percentage" do
      let(:project_slo) { { "availability_pct" => 140 } }

      it "reads as NOT DECLARED rather than inheriting a wider rung" do
        expect(mission.service_level_targets.availability_pct).to be_nil
      end
    end
  end

  describe "cost_ceiling_usd" do
    context "when only the PROJECT declares it" do
      let(:project_slo) { { "cost_ceiling_usd" => 500 } }

      it "resolves off the project" do
        expect(mission.service_level_targets.cost_ceiling_usd).to eq(500.0)
      end
    end

    it "accepts a value far above 100 — it is dollars, not a percentage" do
      mission = build_mission
      mission.update!(configuration: mission.configuration.merge(
        "slo_targets" => { "cost_ceiling_usd" => 25_000 }
      ))

      expect(mission.reload.service_level_targets.cost_ceiling_usd).to eq(25_000.0)
    end

    context "when only the mission BRIEF carries a budget cap" do
      let(:mission_brief) { { "budget_cap_usd_monthly" => 250 } }

      it "falls back to it, exactly as the consumer did before this reader" do
        expect(mission.service_level_targets.cost_ceiling_usd).to eq(250.0)
      end
    end

    context "when the project declares a ceiling AND the brief carries a budget cap" do
      let(:project_slo)   { { "cost_ceiling_usd" => 500 } }
      let(:mission_brief) { { "budget_cap_usd_monthly" => 250 } }

      it "puts the PROJECT above the brief" do
        # budget_cap_usd_monthly is a REQUIRED brief field, so every completed
        # provisioning brief carries one. Above the project it could never be
        # outranked, and a project-declared ceiling would be unobserved for
        # every provisioning mission — the very defect this reader closes.
        expect(mission.service_level_targets.cost_ceiling_usd).to eq(500.0)
      end
    end
  end

  describe "min_throughput_bytes_per_s" do
    context "when only the PROJECT declares it" do
      let(:project_slo) { { "min_throughput_bytes_per_s" => 1_250_000 } }

      it "resolves off the project" do
        expect(mission.service_level_targets.min_throughput_bytes_per_s).to eq(1_250_000.0)
      end
    end

    it "stays declared-only — no floor appears for a project that said nothing" do
      expect(mission.service_level_targets.min_throughput_bytes_per_s).to be_nil
    end
  end

  describe "p99_latency_ms" do
    it "is UNDECLARABLE, and says so rather than reading as an unpopulated gap" do
      targets = mission.service_level_targets

      expect(targets.p99_latency_ms).to be_nil
      expect(targets.undeclarable).to include("p99_latency_ms")
      expect(targets.undeclarable_reason("p99_latency_ms")).to match(/no producer/i)
    end

    context "even when somebody declares one anyway" do
      let(:project_slo) { { "p99_latency_ms" => 250 } }

      it "still reports undeclarable and resolves no value" do
        # Honouring it would state a target the platform cannot measure, which
        # is a claim rather than an observation.
        expect(mission.service_level_targets.p99_latency_ms).to be_nil
        expect(mission.service_level_targets.undeclarable).to include("p99_latency_ms")
      end
    end
  end

  describe "the additive guarantee" do
    it "a mission with NO project resolves exactly as it did before the rung existed" do
      orphan = build_mission(with_project: false)
      orphan.update!(configuration: {
        "slo_targets" => { "availability_pct" => 99.0 },
        "brief" => { "budget_cap_usd_monthly" => 100 }
      })

      targets = orphan.reload.service_level_targets

      expect(orphan.project).to be_nil
      expect(targets.availability_pct).to eq(99.0)
      expect(targets.cost_ceiling_usd).to eq(100.0)
      expect(targets.min_throughput_bytes_per_s).to be_nil
    end

    it "does not raise on a garbled configuration" do
      broken = build_mission
      broken.update_column(:configuration, { "slo_targets" => "nope", "brief" => 7 })

      expect { broken.reload.service_level_targets }.not_to raise_error
      expect(broken.service_level_targets.availability_pct).to be_nil
    end
  end

  describe "#to_h" do
    let(:project_slo) { { "availability_pct" => 99.9, "cost_ceiling_usd" => 500 } }

    it "hands the consumer one hash keyed by the canonical metric names" do
      hash = mission.service_level_targets.to_h

      expect(hash["availability_pct"]).to eq(99.9)
      expect(hash["cost_ceiling_usd"]).to eq(500.0)
      expect(hash).to have_key("min_throughput_bytes_per_s")
      expect(hash).to have_key("p99_latency_ms")
    end
  end
end
