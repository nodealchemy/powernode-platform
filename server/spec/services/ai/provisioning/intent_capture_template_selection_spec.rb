# frozen_string_literal: true

require "rails_helper"

# preferred_template on the brief (IMP 019fe3a7-266d).
#
# There was no operator-facing way to choose a node template: the composer
# always took the account's OLDEST (resolve_default_template), which on ops-hub
# is "base" — blank boot_mode => cloud_init => no agent => module assignment and
# the DockerHost handshake unreachable by construction. The step prose named
# "powernode-ops-cell" while execution_config carried "base" (run 20260808a F3).
#
# Same design as preferred_provider (IMP-019fe47a): the account's templates are
# an authoritative enumerable set, so the choice is never free-generated —
# closed-set prompt, deterministic text-evidence override, keep-with-warn for
# unconfigured values so the ask-path retains the operator's signal.
RSpec.describe Ai::Provisioning::IntentCaptureService, "template selection", type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  subject(:service) { described_class.new(account: account, user: user) }

  def llm_brief(overrides = {})
    {
      "intent" => "provision a 3-node Powernode stack",
      "use_case" => "database",
      "scale" => { "initial" => 3, "target" => 3, "growth_profile" => "steady" },
      "regions" => %w[dna rna],
      "budget_cap_usd_monthly" => 5
    }.merge(overrides)
  end

  def capture(text:, llm: {})
    allow(service).to receive(:extract_brief_from_llm).and_return(llm_brief(llm))
    service.capture(natural_language: text)[:brief]
  end

  context "with a configured template catalog (mirrors ops-hub)" do
    before { skip "system extension not loaded" unless defined?(::System::NodeTemplate) }

    let!(:uefi_template) do
      create(:system_node_template, account: account, name: "powernode-ops-cell",
                                    config: { "boot_mode" => "uefi_disk" })
    end
    let!(:base_template) do
      create(:system_node_template, account: account, name: "pn-base-image", config: {})
    end

    before do
      # The account factory bootstraps templates (M1 self-serve). Clear all but
      # this spec's two so the premise is exact.
      ::System::NodeTemplate.where(account_id: account.id)
                            .where.not(id: [uefi_template.id, base_template.id]).destroy_all
    end

    it "premise: catalog is exactly the two templates above" do
      expect(::System::NodeTemplate.where(account_id: account.id).pluck(:name))
        .to match_array(%w[powernode-ops-cell pn-base-image])
    end

    it "fills preferred_template from text evidence when the LLM omitted it" do
      brief = capture(
        text: "Provision a 3-node stack cloned from powernode-ops-cell across dna and rna",
        llm: {}
      )
      expect(brief["preferred_template"]).to eq("powernode-ops-cell")
    end

    it "overrides a misextracted template when the text names one" do
      brief = capture(
        text: "Provision a stack from the powernode-ops-cell template",
        llm: { "preferred_template" => "pn-base-image" }
      )
      expect(brief["preferred_template"]).to eq("powernode-ops-cell")
    end

    it "normalizes a template referenced by id to its name" do
      brief = capture(text: "spin up a stack", llm: { "preferred_template" => uefi_template.id })
      expect(brief["preferred_template"]).to eq("powernode-ops-cell")
    end

    it "keeps — but warns about — a template the account does not have" do
      expect(Rails.logger).to receive(:warn).with(/matches no configured template/).at_least(:once)
      allow(Rails.logger).to receive(:warn).and_call_original
      brief = capture(text: "spin up a stack", llm: { "preferred_template" => "golden-image-9" })
      expect(brief["preferred_template"]).to eq("golden-image-9")
    end

    it "leaves preferred_template nil when nothing names one" do
      brief = capture(text: "spin up a stack", llm: {})
      expect(brief["preferred_template"]).to be_nil
    end

    it "does not override when the text names MORE THAN ONE template" do
      brief = capture(
        text: "use powernode-ops-cell, not pn-base-image",
        llm: { "preferred_template" => "pn-base-image" }
      )
      expect(brief["preferred_template"]).to eq("pn-base-image")
    end

    it "enumerates the templates as a closed set in the prompt, with boot_mode" do
      prompt = service.send(:build_brief_prompt, "provision a stack", {}, :capture)
      expect(prompt).to include("preferred_template")
      expect(prompt).to include("powernode-ops-cell")
      expect(prompt).to include("pn-base-image")
      expect(prompt).to match(/uefi_disk/)
    end
  end

  context "core mode / empty catalog" do
    it "omits the closed-set template rule but still defines the field" do
      allow(described_class).to receive(:provider_catalog_available?).and_return(false)
      allow(service).to receive(:configured_templates).and_return([])
      prompt = service.send(:build_brief_prompt, "provision a stack", {}, :capture)
      expect(prompt).to include("preferred_template")
    end

    it "passes an extracted value through untouched" do
      allow(service).to receive(:configured_templates).and_return([])
      allow(service).to receive(:extract_brief_from_llm).and_return(
        llm_brief("preferred_template" => "golden")
      )
      brief = service.capture(natural_language: "spin up a stack")[:brief]
      expect(brief["preferred_template"]).to eq("golden")
    end
  end
end
