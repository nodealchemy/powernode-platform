# frozen_string_literal: true

require "rails_helper"

# The classifier extracted in IMP-8e1ac4a09e82 so the platform's two network
# resolvers share one vocabulary — Ai::Provisioning::PlanComposerService
# (compose time) and System::ProvisioningService#sdwan_network_for (provision
# time). Its behaviour through each consumer is covered by that consumer's own
# specs; these examples pin the buckets themselves, because a drift here is
# exactly the class of bug the extraction exists to prevent.
RSpec.describe Shared::SdwanNetworkResolution do
  describe ".classify_value" do
    # "No opinion" — inherit the next arm. Builders and forms emit these
    # routinely, so neither may read as an opt-out nor as a loud failure.
    it "buckets nil, blank and false as :absent" do
      expect(described_class.classify_value(nil)).to eq([ :absent, nil ])
      expect(described_class.classify_value("")).to eq([ :absent, nil ])
      expect(described_class.classify_value("   ")).to eq([ :absent, nil ])
      expect(described_class.classify_value(false)).to eq([ :absent, nil ])
    end

    it "buckets the opt-out sentinel as :opt_out, case-insensitively and stripped" do
      expect(described_class.classify_value("none")).to eq([ :opt_out, "none" ])
      expect(described_class.classify_value("NONE")).to eq([ :opt_out, "NONE" ])
      expect(described_class.classify_value("  None  ")).to eq([ :opt_out, "None" ])
    end

    # Structurally incapable of being an id — the only bucket that is a
    # misconfiguration rather than a choice.
    it "buckets a non-blank non-String as :unusable, carrying the raw value" do
      expect(described_class.classify_value(12_345)).to eq([ :unusable, 12_345 ])
      expect(described_class.classify_value(true)).to eq([ :unusable, true ])
      expect(described_class.classify_value([ "net-1" ])).to eq([ :unusable, [ "net-1" ] ])
    end

    # IMP-5a7aa42515d6: numeric ZERO is the emit-anyway phenomenon in a
    # different type, not an operator decision. `nil` and `""` are :absent
    # because builders and forms emit the key regardless; a serializer that
    # coerces an unset id field (`params[:sdwan_network_id].to_i`, a numeric
    # column default, a form that types the field as a number) emits 0 from
    # exactly the same "nobody chose anything" state.
    it "buckets a numeric zero as :absent" do
      expect(described_class.classify_value(0)).to eq([ :absent, nil ])
      expect(described_class.classify_value(0.0)).to eq([ :absent, nil ])
    end

    # The narrowness is the point: a NON-zero number is someone putting a
    # number where a UUID belongs, which stays the loud misconfiguration.
    it "keeps a non-zero numeric as :unusable" do
      expect(described_class.classify_value(1)).to eq([ :unusable, 1 ])
      expect(described_class.classify_value(-1)).to eq([ :unusable, -1 ])
      expect(described_class.classify_value(0.5)).to eq([ :unusable, 0.5 ])
    end

    # A STRING "0" is a different case and deliberately untouched: it is a
    # non-blank String, so it stamps and fails loud at run time ("sdwan network
    # not found") rather than silently composing bare compute.
    it "leaves a string zero as :usable" do
      expect(described_class.classify_value("0")).to eq([ :usable, "0" ])
    end

    # Existence is deliberately NOT decided here: core cannot check it without
    # naming the extension, and a dead id is already loud at run time.
    it "buckets any other non-blank String as :usable, stripped" do
      expect(described_class.classify_value("net-1")).to eq([ :usable, "net-1" ])
      expect(described_class.classify_value("  net-1  ")).to eq([ :usable, "net-1" ])
      expect(described_class.classify_value("no-such-network")).to eq([ :usable, "no-such-network" ])
    end
  end

  describe ".classify_config" do
    it "reads the key under either a String or a Symbol" do
      expect(described_class.classify_config({ "sdwan_network_id" => "net-1" })).to eq([ :usable, "net-1" ])
      expect(described_class.classify_config({ sdwan_network_id: "net-1" })).to eq([ :usable, "net-1" ])
    end

    it "treats an absent key and a non-Hash blob as :absent" do
      expect(described_class.classify_config({ "other" => "net-1" })).to eq([ :absent, nil ])
      expect(described_class.classify_config({})).to eq([ :absent, nil ])
      expect(described_class.classify_config(nil)).to eq([ :absent, nil ])
      expect(described_class.classify_config("not-a-hash")).to eq([ :absent, nil ])
    end

    it "applies the same buckets to a declared value" do
      expect(described_class.classify_config({ "sdwan_network_id" => "none" })).to eq([ :opt_out, "none" ])
      expect(described_class.classify_config({ "sdwan_network_id" => "" })).to eq([ :absent, nil ])
      expect(described_class.classify_config({ "sdwan_network_id" => 12_345 })).to eq([ :unusable, 12_345 ])
      expect(described_class.classify_config({ "sdwan_network_id" => 0 })).to eq([ :absent, nil ])
    end
  end

  describe ".classify_account_default" do
    it "classifies the account's configured default" do
      account = Account.new(settings: { Account::DEFAULT_SDWAN_NETWORK_SETTING => "net-7" })
      expect(described_class.classify_account_default(account)).to eq([ :usable, "net-7" ])
    end

    it "reports :absent for an unset default and for no account at all" do
      expect(described_class.classify_account_default(Account.new(settings: {}))).to eq([ :absent, nil ])
      expect(described_class.classify_account_default(nil)).to eq([ :absent, nil ])
    end

    # "Explicitly no default" — the resolvers treat it like :absent, since
    # there is no further arm for it to beat.
    it "carries the opt-out sentinel through from the account surface" do
      account = Account.new(settings: { Account::DEFAULT_SDWAN_NETWORK_SETTING => "none" })
      expect(described_class.classify_account_default(account)).to eq([ :opt_out, "none" ])
    end

    # IMP-5a7aa42515d6 reaches this arm too, and deliberately: a settings form
    # that writes 0 for "unset" means "no default", which is what :absent
    # already means here. A non-zero number stays the loud misconfiguration.
    it "reads a zero account default as :absent and a non-zero number as :unusable" do
      zero = Account.new(settings: { Account::DEFAULT_SDWAN_NETWORK_SETTING => 0 })
      expect(described_class.classify_account_default(zero)).to eq([ :absent, nil ])

      numeric = Account.new(settings: { Account::DEFAULT_SDWAN_NETWORK_SETTING => 12_345 })
      expect(described_class.classify_account_default(numeric)).to eq([ :unusable, 12_345 ])
    end
  end

  # The composer aliases the key rather than restating it; if that regresses to
  # a second literal, the two resolvers can drift apart again.
  #
  # This has to be a SOURCE assertion, not a runtime one. Ruby interns frozen
  # string literals process-wide, so with `# frozen_string_literal: true` in
  # both files a re-declared `NETWORK_CONFIG_KEY = "sdwan_network_id"` is the
  # very same object as the alias — `equal?` returns true and cannot tell an
  # alias from the drift it is supposed to catch.
  describe "one definition of the key and the sentinel" do
    let(:composer_source) do
      File.read(Rails.root.join("app/services/ai/provisioning/plan_composer_service.rb"))
    end

    it "reads the key from this module instead of re-declaring the literal" do
      expect(Ai::Provisioning::PlanComposerService::NETWORK_CONFIG_KEY)
        .to eq(described_class::NETWORK_CONFIG_KEY)
      expect(composer_source).not_to match(/NETWORK_CONFIG_KEY\s*=\s*['"]/)
    end

    it "does not re-declare the opt-out sentinel at all" do
      expect(Ai::Provisioning::PlanComposerService.const_defined?(:NETWORK_OPT_OUT_VALUE, false))
        .to be(false)
      expect(composer_source).not_to match(/NETWORK_OPT_OUT_VALUE\s*=\s*['"]/)
    end
  end
end
