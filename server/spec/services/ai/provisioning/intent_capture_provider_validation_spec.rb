# frozen_string_literal: true

require "rails_helper"

# Coverage for preferred_provider VALIDATION in the captured brief (IMP 019fe1e0-71b1).
#
# The LLM extracts brief["preferred_provider"] from free text. Before this guard
# the value was stringified and passed through unchecked, so it could name a
# provider type the account does not have. Downstream,
# PlanComposerService#resolve_provider_choice matches it case-insensitively
# against provider_type and, on no match, falls through to the multi-provider
# clarification path.
#
# Two failure modes that motivated this:
#   (a) a hallucinated-but-absent type silently degrades to clarification;
#   (b) worse, a hallucinated type that HAPPENS to match a different configured
#       provider routes the whole plan to the wrong cloud, with no error.
#
# Observed live on ops-hub 2026-08-08: an objective explicitly naming
# "the 'IPNode PVE' provider (019f73b2-...)" produced preferred_provider
# 'pro_cloud' — a type not configured on that account at all.
#
# Note the operator-ergonomics half: people write the provider's NAME
# ("IPNode PVE"), not its type ("proxmox"). Accepting name and id, and
# normalizing to the type the downstream matcher expects, is what makes the
# common case work rather than degrade to a clarification prompt.
RSpec.describe Ai::Provisioning::IntentCaptureService, "preferred_provider validation", type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  subject(:service) { described_class.new(account: account, user: user) }

  # Minimum viable brief; only preferred_provider varies per example.
  def llm_brief(preferred)
    {
      "intent" => "provision a 3-node Powernode stack",
      "use_case" => "database",
      "scale" => { "initial" => 3, "target" => 3, "growth_profile" => "steady" },
      "regions" => %w[dna rna],
      "budget_cap_usd_monthly" => 5,
      "preferred_provider" => preferred
    }
  end

  def capture_with(preferred)
    allow(service).to receive(:extract_brief_from_llm).and_return(llm_brief(preferred))
    service.capture(natural_language: "provision a 3-node stack")[:brief]
  end

  context "when the system extension supplies providers" do
    before do
      skip "system extension not loaded" unless defined?(::System::Provider)
      # The account factory ships a default "Pro Cloud"/pro_cloud provider.
      # Clear it so this account's catalog is EXACTLY the two below — otherwise
      # 'pro_cloud' is legitimately configured here and the absent-provider case
      # silently stops testing anything.
      ::System::Provider.where(account_id: account.id).destroy_all
      ::System::Provider.create!(account: account, name: "IPNode PVE", provider_type: "proxmox", enabled: true)
      ::System::Provider.create!(account: account, name: "local-qemu", provider_type: "local_qemu", enabled: true)
    end

    it "the account's catalog is exactly the two configured providers" do
      # Guards the premise of every example below.
      expect(::System::Provider.where(account_id: account.id, enabled: true).pluck(:provider_type))
        .to match_array(%w[proxmox local_qemu])
    end

    it "keeps — but warns about — a provider type the account does not have" do
      # 'pro_cloud' is a real type in the seed catalog but is NOT configured
      # here. It is deliberately preserved: nil and an unmatched value both
      # reach the same downstream outcome (clarification), so discarding it
      # would lose the operator's stated intent for no behavioural gain.
      # See the note in #normalize_preferred_provider.
      expect(Rails.logger).to receive(:warn).with(/matches no configured provider/)
      expect(capture_with("pro_cloud")["preferred_provider"]).to eq("pro_cloud")
    end

    it "keeps a configured provider type" do
      expect(capture_with("proxmox")["preferred_provider"]).to eq("proxmox")
    end

    it "resolves a provider referenced by DISPLAY NAME to its type" do
      # This is what an operator actually writes.
      expect(capture_with("IPNode PVE")["preferred_provider"]).to eq("proxmox")
    end

    it "resolves a provider referenced by id to its type" do
      id = ::System::Provider.find_by(account_id: account.id, provider_type: "proxmox").id
      expect(capture_with(id)["preferred_provider"]).to eq("proxmox")
    end

    it "matches case-insensitively and ignores surrounding whitespace" do
      expect(capture_with("  ipnode pve  ")["preferred_provider"]).to eq("proxmox")
    end

    it "leaves an absent preferred_provider as nil" do
      expect(capture_with(nil)["preferred_provider"]).to be_nil
    end

    it "still scrubs regions when the operator names a LOCAL provider" do
      # The existing local-provider region scrub keys off the normalized type,
      # so it must keep working when the operator wrote the display name.
      brief = capture_with("local-qemu")
      expect(brief["preferred_provider"]).to eq("local_qemu")
      expect(brief["regions"]).to eq([])
    end

    # These two probe SCOPING. Both reference the provider by a display name
    # that differs from its type, so a scoping leak is directly observable: if
    # the out-of-scope provider were consulted the value would be rewritten to
    # its type ("aws" / "gcp"). Staying as the raw name proves it was not.
    it "does not consider a provider belonging to another account" do
      other = create(:account)
      ::System::Provider.create!(account: other, name: "Foreign Cloud", provider_type: "aws", enabled: true)
      expect(capture_with("Foreign Cloud")["preferred_provider"]).to eq("Foreign Cloud")
    end

    it "does not consider a disabled provider" do
      ::System::Provider.create!(account: account, name: "Old GCP", provider_type: "gcp", enabled: false)
      expect(capture_with("Old GCP")["preferred_provider"]).to eq("Old GCP")
    end
  end

  context "when the system extension is absent (core mode)" do
    it "passes the value through rather than nulling everything" do
      # Core mode has no provider catalog to validate against; silently nulling
      # every preferred_provider would be a regression, not a safety win.
      allow(Ai::Provisioning::IntentCaptureService)
        .to receive(:provider_catalog_available?).and_return(false)
      expect(capture_with("proxmox")["preferred_provider"]).to eq("proxmox")
    end
  end
end
