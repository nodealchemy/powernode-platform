# frozen_string_literal: true

require "rails_helper"

# Coverage for region resolution in PlanComposerService (part of IMP 019fe1e0-0b8a).
#
# `resolve_region_for_brief` matched the brief's region string against
# System::ProviderRegion#name ONLY, then fell back to `scope.first` on no match.
# Two problems:
#
#   1. region_code — not name — is the canonical identifier. For the Proxmox
#      provider the platform's own doc comment states "regions model PVE nodes,
#      so region_code IS the node name" (proxmox_provider.rb). A region whose
#      name differs from its code was therefore unfindable by code.
#   2. The `|| scope.first` fallback is SILENT. An unmatched region does not
#      raise, warn, or record anything — it places the instances on an arbitrary
#      region and the plan looks entirely normal. On a live multi-node cluster
#      that is a wrong-node deployment with no signal.
#
# Both matter because a plan that reads correct and places elsewhere is the
# failure mode the review_plan gate exists to catch, and the one a headless
# harness (P2) would sail straight past.
RSpec.describe Ai::Provisioning::PlanComposerService, "region resolution", type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:mission) { create(:ai_mission, account: account, created_by: user, mission_type: "infrastructure") }

  subject(:service) { described_class.new(account: account, mission: mission) }

  before do
    skip "system extension not loaded" unless defined?(::System::ProviderRegion)
    # The account factory ships a Pro Cloud provider with us-east-1/us-west-1
    # regions. Clear them so `scope.first` is one of THIS spec's regions —
    # otherwise the arbitrary-fallback assertions pass against a factory region
    # and stop testing the thing they name.
    ::System::ProviderRegion.where(account_id: account.id).destroy_all
    ::System::Provider.where(account_id: account.id).destroy_all
  end

  let(:sys_provider) do
    ::System::Provider.create!(account: account, name: "IPNode PVE", provider_type: "proxmox", enabled: true)
  end

  def resolve(regions)
    service.send(:resolve_region_for_brief, { "regions" => regions })
  end

  describe "matching by region_code" do
    let!(:dna) do
      ::System::ProviderRegion.create!(
        account: account, provider: sys_provider, region_code: "dna", name: "Datacentre North A", enabled: true
      )
    end
    let!(:rna) do
      ::System::ProviderRegion.create!(
        account: account, provider: sys_provider, region_code: "rna", name: "Datacentre North B", enabled: true
      )
    end

    it "resolves a region named by its region_code" do
      # The operator/brief says "rna" — the PVE node name, i.e. the region_code.
      expect(resolve(["rna"])).to eq(rna)
    end

    it "does not silently land on an arbitrary region when the code matches" do
      # Guards the specific failure: `scope.first` here would be dna, and the
      # instances would deploy to the wrong physical node with no signal.
      expect(resolve(["rna"])).not_to eq(dna)
    end

    it "still resolves a region named by its display name" do
      expect(resolve(["Datacentre North B"])).to eq(rna)
    end

    it "matches case-insensitively and ignores surrounding whitespace" do
      expect(resolve(["  RNA  "])).to eq(rna)
    end
  end

  describe "when the brief names a region that does not exist" do
    let!(:dna) do
      ::System::ProviderRegion.create!(
        account: account, provider: sys_provider, region_code: "dna", name: "dna", enabled: true
      )
    end

    it "warns rather than silently substituting a different region" do
      # The fallback itself is preserved — composition should not hard-fail on a
      # sloppy region string — but it must not be silent, because the result is
      # a real placement decision the operator never made.
      expect(Rails.logger).to receive(:warn).with(/no region matching .*fna/i)
      resolve(["fna"])
    end

    it "still returns a usable region so composition can proceed" do
      allow(Rails.logger).to receive(:warn)
      expect(resolve(["fna"])).to eq(dna)
    end
  end

  describe "when the brief names MORE THAN ONE region" do
    let!(:dna) do
      ::System::ProviderRegion.create!(
        account: account, provider: sys_provider, region_code: "dna", name: "dna", enabled: true
      )
    end
    let!(:rna) do
      ::System::ProviderRegion.create!(
        account: account, provider: sys_provider, region_code: "rna", name: "rna", enabled: true
      )
    end

    # This resolver deliberately returns only the FIRST region — it stamps the
    # initial provider_region_id, and #fan_out_regions! then splits the step
    # across every named region. The earlier "the rest will NOT be provisioned"
    # warning was removed alongside that change: it would now be false.
    # Distribution itself is covered by plan_composer_multi_region_spec.rb.
    it "returns the first named region" do
      expect(resolve(%w[dna rna])).to eq(dna)
    end

    it "does not warn that the other regions are dropped — they are not" do
      expect(Rails.logger).not_to receive(:warn).with(/will NOT be provisioned/)
      resolve(%w[dna rna])
    end
  end

  describe "when the brief names no region at all" do
    let!(:dna) do
      ::System::ProviderRegion.create!(
        account: account, provider: sys_provider, region_code: "dna", name: "dna", enabled: true
      )
    end

    it "falls back without warning — there is no operator intent to contradict" do
      expect(Rails.logger).not_to receive(:warn).with(/no region matching/i)
      expect(resolve([])).to eq(dna)
    end
  end
end
