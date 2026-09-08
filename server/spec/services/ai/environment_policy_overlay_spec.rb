# frozen_string_literal: true

require "rails_helper"

# Environment campaign, increment 3 — the overlay only ever ESCALATES.
RSpec.describe Ai::EnvironmentPolicyOverlay do
  let(:account) { create(:account) }
  let(:dev)  { account.environments.find_by!(slug: "dev") }
  let(:prod) { account.environments.find_by!(slug: "prod") }
  let(:ops)  { account.environments.find_by!(slug: "ops") }
  let(:relaxed) { { policy: "auto_approve", channels: [], conditions: {}, record: nil } }

  it "leaves a verdict alone when the environment is unknown" do
    expect(described_class.apply(relaxed, environment: nil, action_category: "system.task.terminate")).to eq(relaxed)
  end

  it "leaves a reversible action alone in dev and in the protected-but-monitored control plane" do
    %w[system.instance.provision system.template.update].each do |category|
      expect(described_class.apply(relaxed, environment: dev, action_category: category)[:policy]).to eq("auto_approve")
      expect(described_class.apply(relaxed, environment: ops, action_category: category)[:policy]).to eq("auto_approve")
    end
  end

  it "parks a destructive action in a protected environment and says why" do
    %w[system.task.terminate sdwan.peer_delete system.instance.reboot system.node_boot_image_drift
       system.platforms.rollback_disk_image system.instance_pool_drain system.migrations.apply].each do |category|
      out = described_class.apply(relaxed, environment: ops, action_category: category)
      expect(out[:policy]).to eq("require_approval")
      expect(out[:environment_escalation]).to include("ops").and include("destructive")
    end
    expect(described_class.apply(relaxed, environment: dev, action_category: "system.task.terminate")[:policy]).to eq("auto_approve")
  end

  it "parks everything in prod, which is seeded supervised (operator ruling: anything touching prod needs a person)" do
    out = described_class.apply(relaxed, environment: prod, action_category: "system.instance.provision")
    expect(out[:policy]).to eq("require_approval")
    expect(out[:environment_escalation]).to include("supervised")
  end

  # The defaults are anchored on the VERB: a signal or observation kind that
  # merely mentions one is not a destructive action.
  it "does not treat a signal kind that mentions a destructive verb as destructive" do
    %w[system.boot_image_stale system.pool.terminate_failed platform.resilience.drain_started
       system.unclaimed_devices_reaped system.migrations.cancel].each do |kind|
      expect(described_class.apply(relaxed, environment: ops, action_category: kind)[:policy]).to eq("auto_approve"), kind
    end
  end

  it "honours the environment's own approval_required_categories globs" do
    dev.update!(approval_required_categories: [ "sdwan.*" ])
    expect(described_class.apply(relaxed, environment: dev, action_category: "sdwan.network_create")[:policy]).to eq("require_approval")
    expect(described_class.apply(relaxed, environment: dev, action_category: "system.instance.provision")[:policy]).to eq("auto_approve")
  end

  it "never relaxes a block or an existing park" do
    blocked = relaxed.merge(policy: "block")
    parked  = relaxed.merge(policy: "require_approval")
    expect(described_class.apply(blocked, environment: dev, action_category: "x.y")[:policy]).to eq("block")
    expect(described_class.apply(parked, environment: dev, action_category: "x.y")[:policy]).to eq("require_approval")
  end

  # `silent` is an operator's quiet "never"; rewriting it into require_approval
  # would hand the action to an approval audience — a fail-open.
  it "never turns a silent refusal into an approval request" do
    silent = relaxed.merge(policy: "silent")
    expect(described_class.apply(silent, environment: prod, action_category: "system.task.terminate")[:policy]).to eq("silent")
  end

  it "reads the destructive family list from the SiteSetting when set" do
    SiteSetting.set(described_class::DESTRUCTIVE_SETTING_KEY, "custom.*", setting_type: "string")
    expect(described_class.apply(relaxed, environment: ops, action_category: "custom.thing")[:policy]).to eq("require_approval")
    expect(described_class.apply(relaxed, environment: ops, action_category: "system.task.terminate")[:policy]).to eq("auto_approve")
  ensure
    SiteSetting.find_by(key: described_class::DESTRUCTIVE_SETTING_KEY)&.destroy
  end
end
