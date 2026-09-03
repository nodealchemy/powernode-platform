# frozen_string_literal: true

require "rails_helper"

# IMP-e025722ef14e — a project's declared SNAPSHOT policy has a home.
#
# APO-5 gave a project's volumes a snapshot and a restore, but nothing
# enforced a schedule: no project could declare "snapshot every N hours,
# keep the last M", so no sensor could ever ask whether one was overdue.
# The reader lives here for the reason APO-3a moved the scaling window here
# — a project's declared numbers have ONE home, or the sensor that fires
# and the applier that acts hold different opinions of the same project.
#
# Resolution mirrors #scaling_bounds: mission `watch_policies` → the mission
# TEMPLATE's default_configuration → Account#settings → SiteSetting → the
# constant fallback. Both constants are 0, deliberately: an undeclared
# project is neither scheduled nor pruned. Scheduling creates provider-side
# snapshots (money, per tick, forever) and pruning destroys restore points,
# so neither is a default a code change gets to choose.
RSpec.describe Ai::Mission, "#snapshot_policy" do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  def mission_with(watch_policies: nil, template: nil)
    cfg = {}
    cfg["watch_policies"] = watch_policies if watch_policies
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

  # THE SHIPPED DEFAULT, pinned as a literal: a comparison against the
  # constants would stay green if someone gave either one a number, and a
  # number here is not a neutral choice.
  it "ships NO schedule and NO retention — an undeclared project is untouched" do
    expect(described_class::DEFAULT_SNAPSHOT_INTERVAL_HOURS).to eq(0)
    expect(described_class::DEFAULT_SNAPSHOT_RETENTION_COUNT).to eq(0)

    policy = mission_with.snapshot_policy
    expect(policy.interval_hours).to eq(0)
    expect(policy.retention_count).to eq(0)
    expect(policy).not_to be_scheduled
    expect(policy).not_to be_prunes
  end

  it "reads the project's own watch_policies" do
    mission = mission_with(watch_policies: {
      described_class::SNAPSHOT_INTERVAL_HOURS_POLICY_KEY => 6,
      described_class::SNAPSHOT_RETENTION_COUNT_POLICY_KEY => 4
    })

    policy = mission.snapshot_policy
    expect(policy.interval_hours).to eq(6)
    expect(policy.retention_count).to eq(4)
    expect(policy).to be_scheduled
    expect(policy).to be_prunes
  end

  it "reads a policy declared on the mission TEMPLATE's default_configuration" do
    template = create(
      :ai_mission_template,
      account: account,
      default_configuration: {
        "watch_policies" => { described_class::SNAPSHOT_INTERVAL_HOURS_POLICY_KEY => 24 }
      }
    )

    expect(mission_with(template: template).snapshot_policy.interval_hours).to eq(24)
  end

  it "resolves a SiteSetting default rather than a hardcoded literal" do
    SiteSetting.set(described_class::SNAPSHOT_INTERVAL_HOURS_SETTING, "12")
    SiteSetting.set(described_class::SNAPSHOT_RETENTION_COUNT_SETTING, "7")

    policy = mission_with.snapshot_policy
    expect(policy.interval_hours).to eq(12)
    expect(policy.retention_count).to eq(7)
  end

  it "lets the account's settings override the SiteSetting" do
    SiteSetting.set(described_class::SNAPSHOT_INTERVAL_HOURS_SETTING, "12")
    account.update!(settings: { described_class::SNAPSHOT_INTERVAL_HOURS_SETTING => 3 })

    expect(mission_with.snapshot_policy.interval_hours).to eq(3)
  end

  it "lets the project's own declaration win over every wider default" do
    SiteSetting.set(described_class::SNAPSHOT_RETENTION_COUNT_SETTING, "7")
    account.update!(settings: { described_class::SNAPSHOT_RETENTION_COUNT_SETTING => 5 })

    mission = mission_with(watch_policies: { described_class::SNAPSHOT_RETENTION_COUNT_POLICY_KEY => 2 })
    expect(mission.snapshot_policy.retention_count).to eq(2)
  end

  # PRESENCE IS DECISIVE, exactly as for a scaling bound: a project declaring
  # 0 is saying "no schedule here", and falling through to a wider default
  # would silently overrule it — the one direction a policy ladder must never
  # resolve. A garbled declaration reads the same fail-closed way.
  [ 0, -1, "soon" ].each do |declared|
    it "reads a declaration of #{declared.inspect} as OFF rather than inheriting the wider default" do
      SiteSetting.set(described_class::SNAPSHOT_INTERVAL_HOURS_SETTING, "12")
      mission = mission_with(watch_policies: { described_class::SNAPSHOT_INTERVAL_HOURS_POLICY_KEY => declared })

      expect(mission.snapshot_policy.interval_hours).to eq(0)
      expect(mission.snapshot_policy).not_to be_scheduled
    end
  end

  it "treats a blank declaration as absent and falls through to the next rung" do
    SiteSetting.set(described_class::SNAPSHOT_INTERVAL_HOURS_SETTING, "12")
    mission = mission_with(watch_policies: { described_class::SNAPSHOT_INTERVAL_HOURS_POLICY_KEY => "" })

    expect(mission.snapshot_policy.interval_hours).to eq(12)
  end

  it "resolves interval and retention independently" do
    SiteSetting.set(described_class::SNAPSHOT_RETENTION_COUNT_SETTING, "3")
    mission = mission_with(watch_policies: { described_class::SNAPSHOT_INTERVAL_HOURS_POLICY_KEY => "abc" })

    policy = mission.snapshot_policy
    expect(policy.interval_hours).to eq(0)
    expect(policy.retention_count).to eq(3)
  end
end
