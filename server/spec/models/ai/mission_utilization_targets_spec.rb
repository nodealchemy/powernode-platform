# frozen_string_literal: true

require "rails_helper"

# IMP-7684d3f8658a — the per-project UTILIZATION ceilings.
#
# APO-3a made Ai::Mission the home for a project's scaling window; the cpu /
# memory ceilings that decide whether a project is utilization-BOUND belong in
# the same home, for the same reason: the SLO sensor and any later reader must
# not each carry a private opinion of a project's declared target.
#
# Resolution mirrors #scaling_bounds — mission `slo_targets` → the mission
# TEMPLATE's default_configuration → Account#settings → SiteSetting → the
# constant fallback. The fleet-wide default is SiteSetting-resolved, never a
# bare literal at a call site; the constant rung is nil, so the check is
# DECLARED-ONLY (see the first example for why that is not a shrug).
RSpec.describe Ai::Mission, "#utilization_targets" do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  def mission_with(slo_targets: nil, template: nil)
    cfg = {}
    cfg["slo_targets"] = slo_targets if slo_targets
    create(
      :ai_mission,
      account: account,
      created_by: user,
      mission_type: "infrastructure",
      custom_phases: [ { "key" => "adapting", "label" => "Adapting", "order" => 0 } ],
      mission_template: template,
      configuration: cfg
    )
  end

  # THE SHIPPED DEFAULT, pinned as a literal rather than against the constants
  # — which is the whole point: an example that only compared the resolved
  # value to DEFAULT_MAX_CPU_PCT would stay green if someone gave the constant
  # a number, and a number here is not a neutral choice.
  #
  # These ceilings are DECLARED-ONLY. A `system.project_slo_violation` on
  # cpu_pct maps to change_type `scale_horizontal`, which is seeded
  # `auto_approve` against the mission's watch_policies window — and the seeded
  # `system_provisioning` template every provisioned project inherits from
  # declares auto_scale_max_replicas 5, so #scaling_bounds.auto_scale_out? is
  # ALREADY true for a project that declared nothing itself. A shipped default
  # would therefore have opened an unattended, money-spending provision path on
  # existing projects the day it merged. Turning the check on is an operator
  # act: a project's own slo_targets, its template, the account, or the
  # fleet-wide SiteSetting.
  it "ships NO default ceiling — an undeclared project is unchecked" do
    expect(described_class::DEFAULT_MAX_CPU_PCT).to be_nil
    expect(described_class::DEFAULT_MAX_MEMORY_PCT).to be_nil

    targets = mission_with.utilization_targets
    expect(targets.cpu_pct).to be_nil
    expect(targets.memory_pct).to be_nil
  end

  # The other half of that decision, pinned so it cannot regress quietly: the
  # seeded project shape really does carry an auto-scale-out window, so the
  # "a default cannot actuate on its own" argument for shipping one is false.
  it "carries an auto-scale-out window from the seeded template rung" do
    template = create(
      :ai_mission_template,
      account: account,
      default_configuration: {
        "watch_policies" => { "auto_scale_min_replicas" => 1, "auto_scale_max_replicas" => 5 }
      }
    )

    expect(mission_with(template: template).scaling_bounds).to be_auto_scale_out
  end

  it "resolves a SiteSetting default rather than a hardcoded literal" do
    SiteSetting.set(described_class::MAX_CPU_PCT_SETTING, "70")
    SiteSetting.set(described_class::MAX_MEMORY_PCT_SETTING, "60")

    targets = mission_with.utilization_targets
    expect(targets.cpu_pct).to eq(70.0)
    expect(targets.memory_pct).to eq(60.0)
  end

  it "lets the account's settings override the SiteSetting" do
    SiteSetting.set(described_class::MAX_CPU_PCT_SETTING, "70")
    account.update!(settings: { described_class::MAX_CPU_PCT_SETTING => 55 })

    expect(mission_with.utilization_targets.cpu_pct).to eq(55.0)
  end

  it "lets the project's own slo_targets win over every wider default" do
    SiteSetting.set(described_class::MAX_CPU_PCT_SETTING, "70")
    account.update!(settings: { described_class::MAX_CPU_PCT_SETTING => 55 })

    mission = mission_with(slo_targets: { described_class::MAX_CPU_PCT_SLO_KEY => 92.5 })
    expect(mission.utilization_targets.cpu_pct).to eq(92.5)
  end

  it "reads a target declared on the mission TEMPLATE's default_configuration" do
    template = create(
      :ai_mission_template,
      account: account,
      default_configuration: { "slo_targets" => { described_class::MAX_MEMORY_PCT_SLO_KEY => 75 } }
    )

    expect(mission_with(template: template).utilization_targets.memory_pct).to eq(75.0)
  end

  # PRESENCE IS DECISIVE, and an unusable declaration resolves to NO TARGET
  # rather than to a wider default. A ceiling of 0 (or 140, or "soon") is not a
  # narrower window, it is an incoherent one — and guessing a number there
  # would fire a breach on every tick of a project whose operator declared
  # something the platform could not read.
  [ 0, -5, 140, "soon" ].each do |bad|
    it "resolves no cpu target for an unusable declaration (#{bad.inspect})" do
      SiteSetting.set(described_class::MAX_CPU_PCT_SETTING, "70")
      mission = mission_with(slo_targets: { described_class::MAX_CPU_PCT_SLO_KEY => bad })

      expect(mission.utilization_targets.cpu_pct).to be_nil
    end
  end

  # DELIBERATELY NOT "unusable": a blank string is the same statement as an
  # ABSENT key, exactly as #resolved_scale_bound reads one, so it falls through
  # to the next rung rather than switching the check off. Pinned because the two
  # ladders must not drift on what "declared nothing" looks like.
  it "treats a blank declaration as absent and falls through to the next rung" do
    SiteSetting.set(described_class::MAX_CPU_PCT_SETTING, "70")
    mission = mission_with(slo_targets: { described_class::MAX_CPU_PCT_SLO_KEY => "" })

    expect(mission.utilization_targets.cpu_pct).to eq(70.0)
  end

  it "accepts a numeric string declaration" do
    mission = mission_with(slo_targets: { described_class::MAX_CPU_PCT_SLO_KEY => "88.5" })
    expect(mission.utilization_targets.cpu_pct).to eq(88.5)
  end

  it "resolves each metric independently — a bad cpu target leaves memory alone" do
    SiteSetting.set(described_class::MAX_MEMORY_PCT_SETTING, "80")
    mission = mission_with(slo_targets: { described_class::MAX_CPU_PCT_SLO_KEY => 0 })

    expect(mission.utilization_targets.cpu_pct).to be_nil
    expect(mission.utilization_targets.memory_pct).to eq(80.0)
  end

  # ---------------------------------------------------------------------
  # The per-tick hoist. SiteSetting.get is an uncached find_by, and the fleet
  # SLO sensor walks every active infrastructure mission on each tick, so the
  # global rung is resolved ONCE and handed in.
  # ---------------------------------------------------------------------
  describe "global_settings: hoist" do
    it "uses a supplied global rung instead of reading the SiteSetting" do
      SiteSetting.set(described_class::MAX_CPU_PCT_SETTING, "70")
      hoisted = { described_class::MAX_CPU_PCT_SETTING => 90 }

      expect(mission_with.utilization_targets(global_settings: hoisted).cpu_pct).to eq(90.0)
    end

    # The reason the lambda tests `key?` and not truthiness: a hoist that
    # resolved the setting to nil has ANSWERED for that rung. Re-reading it
    # here would put the per-mission SELECT back for exactly the common case
    # (nothing set) the hoist exists to make cheap.
    it "treats a hoisted nil as answered — it does not re-read the SiteSetting" do
      SiteSetting.set(described_class::MAX_CPU_PCT_SETTING, "70")
      hoisted = { described_class::MAX_CPU_PCT_SETTING => nil }

      expect(SiteSetting).not_to receive(:get).with(described_class::MAX_CPU_PCT_SETTING)
      expect(mission_with.utilization_targets(global_settings: hoisted).cpu_pct).to be_nil
    end

    # A key the hoist does NOT carry still resolves lazily, so a partial hash
    # cannot silently switch a declared ceiling off.
    it "falls back to a live read for a key the hoist omits" do
      SiteSetting.set(described_class::MAX_MEMORY_PCT_SETTING, "65")
      hoisted = { described_class::MAX_CPU_PCT_SETTING => 90 }

      expect(mission_with.utilization_targets(global_settings: hoisted).memory_pct).to eq(65.0)
    end

    it ".global_utilization_settings resolves both keys, present-with-nil when unset" do
      SiteSetting.set(described_class::MAX_CPU_PCT_SETTING, "70")
      resolved = described_class.global_utilization_settings

      expect(resolved[described_class::MAX_CPU_PCT_SETTING]).to eq("70")
      expect(resolved).to have_key(described_class::MAX_MEMORY_PCT_SETTING)
      expect(resolved[described_class::MAX_MEMORY_PCT_SETTING]).to be_nil
    end
  end
end
