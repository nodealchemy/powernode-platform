# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Deploy::Methods::SudoBridge do
  let(:account) { create(:account) }
  let(:method) { described_class.new(account: account) }
  let(:platform_target) { Ai::Deploy::Target.new(kind: :platform_self, environment: "development") }
  let(:project_target) { Ai::Deploy::Target.new(kind: :project) }

  describe "availability gating" do
    it "is OFF unless the operator opted in via the enable env" do
      expect(described_class.available?).to be false
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with(described_class::ENABLE_ENV).and_return("enabled")
      expect(described_class.available?).to be true
    end

    it "supports platform-self only" do
      expect(described_class.supports?(platform_target)).to be true
      expect(described_class.supports?(project_target)).to be false
    end
  end

  describe "#deploy! dry-run (default)" do
    it "lists the exact systemctl commands for the hardcoded allowlist and runs nothing" do
      expect(Open3).not_to receive(:capture3)
      result = method.deploy!(target: platform_target, ref: "abc123", dry_run: true)
      expect(result).to be_dry_run
      expect(result.commands).to eq(described_class::UNIT_ALLOWLIST.map { |u| "sudo -n systemctl restart #{u}" })
    end

    it "refuses a non-platform-self target" do
      expect(method.deploy!(target: project_target, ref: "x", dry_run: true)).to be_failed
    end
  end

  describe "#deploy! real run" do
    it "restarts every allowlisted unit in order via sudo systemctl" do
      ok = instance_double(Process::Status, success?: true)
      described_class::UNIT_ALLOWLIST.each do |unit|
        expect(Open3).to receive(:capture3).with("sudo", "-n", "systemctl", "restart", unit).and_return(["", "", ok])
      end
      result = method.deploy!(target: platform_target, ref: "abc", dry_run: false)
      expect(result).to be_succeeded
      expect(result.metadata[:restarted]).to eq(described_class::UNIT_ALLOWLIST)
    end

    it "fails fast if a unit restart fails" do
      bad = instance_double(Process::Status, success?: false)
      allow(Open3).to receive(:capture3).and_return(["", "boom", bad])
      result = method.deploy!(target: platform_target, ref: "abc", dry_run: false)
      expect(result).to be_failed
    end
  end

  it "never restarts a unit outside the allowlist (defense-in-depth)" do
    expect(Open3).not_to receive(:capture3)
    expect(method.send(:restart_unit, "powernode-evil@default")).to be false
  end
end
