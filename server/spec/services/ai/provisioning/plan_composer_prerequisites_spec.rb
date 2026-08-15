# frozen_string_literal: true

require "rails_helper"

# Compose-time prerequisite validation (second half of IMP 019fe647).
#
# Run dryrun-20260809c: the composed plan's docker steps failed at RUNTIME on
# 'no SDWAN peer with an assigned overlay address' — the account had zero
# Sdwan::Networks and the chosen template declared none, all knowable at
# compose time. The plan passed the review gate anyway.
#
# The composer now consults the `provision_prerequisites` extension seam after
# rewriting steps: when the checker reports issues, compose! returns the same
# clarification shape resolve_provider_choice uses (both the internal phase
# path and the REST path already render it — IMP 019fe1d8), so the operator
# hears "this plan needs X" at compose time instead of watching steps die.
RSpec.describe Ai::Provisioning::PlanComposerService, "compose-time prerequisites", type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:mission) do
    create(:ai_mission, account: account, created_by: user, mission_type: "infrastructure",
                        configuration: { "brief" => brief })
  end
  let(:brief) do
    {
      "intent" => "provision a stack", "use_case" => "validation",
      "scale" => { "initial" => 1, "target" => 1 }, "regions" => [],
      "budget_cap_usd_monthly" => 5
    }
  end

  subject(:service) { described_class.new(account: account, mission: mission) }

  def stub_checker(checker)
    allow(::Powernode::ExtensionRegistry).to receive(:provider).and_call_original
    allow(::Powernode::ExtensionRegistry).to receive(:provider)
      .with(:provision_prerequisites).and_return(checker)
  end

  describe "#check_plan_prerequisites" do
    let(:plan_steps) do
      [
        { "skill" => "provision_full_stack" },
        { "skill" => "docker_provision" }
      ]
    end

    it "returns a clarification payload when the checker reports issues" do
      # network_id (IMP-94728a788498) carries the composer's three-arm
      # resolution down to the checker; nil means "nothing resolves".
      checker = double("prereqs")
      expect(checker).to receive(:check) do |account:, template_id:, skills:, network_id:|
        expect(account.id).to eq(mission.account_id)
        expect(skills).to include("docker_provision")
        expect(network_id).to be_nil
        [ "docker_provision requires an SDWAN overlay; template declares no sdwan_network_id" ]
      end
      stub_checker(checker)

      result = service.send(:check_plan_prerequisites, skills: %w[provision_full_stack docker_provision],
                                                       template_id: "tmpl-1")
      expect(result).to be_a(Hash)
      expect(result[:clarification_needed]).to be true
      expect(result[:message]).to match(/SDWAN overlay/)
    end

    it "threads the caller-resolved network id through to the checker" do
      checker = double("prereqs")
      expect(checker).to receive(:check) do |network_id:, **|
        expect(network_id).to eq("net-123")
        []
      end
      stub_checker(checker)

      expect(service.send(:check_plan_prerequisites, skills: %w[docker_provision],
                                                     template_id: "tmpl-1",
                                                     network_id: "net-123")).to be_nil
    end

    it "returns nil when the checker reports no issues" do
      stub_checker(double("prereqs", check: []))
      expect(service.send(:check_plan_prerequisites, skills: %w[docker_provision], template_id: "t")).to be_nil
    end

    it "returns nil in core mode (no checker registered)" do
      stub_checker(nil)
      expect(service.send(:check_plan_prerequisites, skills: %w[docker_provision], template_id: "t")).to be_nil
    end

    it "fails OPEN on a checker error — a broken checker must not block composition" do
      checker = double("prereqs")
      allow(checker).to receive(:check).and_raise(StandardError, "boom")
      stub_checker(checker)
      expect(Rails.logger).to receive(:warn).with(/prerequisite check failed/i).at_least(:once)
      allow(Rails.logger).to receive(:warn).and_call_original
      expect(service.send(:check_plan_prerequisites, skills: %w[docker_provision], template_id: "t")).to be_nil
    end
  end
end
