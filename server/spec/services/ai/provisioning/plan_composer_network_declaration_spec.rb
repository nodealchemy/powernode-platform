# frozen_string_literal: true

require "rails_helper"

# #check_network_declaration — the compose-time guard that refuses to silently
# compose bare compute for a plan that asked for the fabric (IMP-cdc1d0703e5a,
# extended to the account arm by IMP-94728a788498).
#
# IMP-5a7aa42515d6 narrows what counts as "asked for the fabric and got a
# broken answer": a numeric ZERO is a builder emitting an unset id, not an
# operator decision, so it must resolve like null/"" — inherit the next arm —
# rather than fail the compose. A NON-zero number stays loud, because a number
# where a UUID belongs is a real decision wrongly made.
RSpec.describe Ai::Provisioning::PlanComposerService, "network declaration check", type: :service do
  before { skip "system extension not loaded" unless defined?(::System::NodeTemplate) }

  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:brief) do
    {
      "intent" => "provision a stack", "use_case" => "validation",
      "scale" => { "initial" => 1, "target" => 1 }, "regions" => [],
      "preferred_template" => "declaring-template"
    }
  end
  let(:mission) do
    create(:ai_mission, account: account, created_by: user, mission_type: "infrastructure",
                        configuration: { "brief" => brief })
  end

  subject(:service) { described_class.new(account: account, mission: mission) }

  def template_with(config)
    create(:system_node_template, account: account, name: "declaring-template", config: config)
  end

  describe "the template arm" do
    it "does NOT fail the compose for a numeric zero — it is an unset id, not a misconfiguration" do
      template_with("sdwan_network_id" => 0)

      expect(service.send(:check_network_declaration, brief)).to be_nil
    end

    it "resolves a numeric zero to no network at all, exactly as a null would" do
      template = template_with("sdwan_network_id" => 0)

      expect(service.send(:template_network_declaration, template)).to eq([ :absent, nil ])
      expect(service.send(:resolved_network_id, template)).to be_nil
    end

    # The over-widening guard. If this ever goes green-by-accident the fix has
    # stopped failing loud where failing loud was correct.
    it "still fails the compose for a NON-zero number" do
      template = template_with("sdwan_network_id" => 12_345)

      result = service.send(:check_network_declaration, brief)
      expect(result).to include(clarification_needed: true)
      expect(result[:network_declaration_issue]).to include(template_id: template.id,
                                                            key: "sdwan_network_id")
    end
  end

  describe "the account-default arm" do
    # The classifier is shared by BOTH arms, so the same narrowing reaches the
    # account default — and should: a settings form writing 0 for "unset" means
    # "no default", which is what :absent already means on this arm.
    it "does NOT fail the compose for a zero account default" do
      template_with("boot_mode" => "uefi_disk")
      account.update!(settings: (account.settings || {}).merge(
        ::Account::DEFAULT_SDWAN_NETWORK_SETTING => 0
      ))

      expect(service.send(:check_network_declaration, brief)).to be_nil
    end

    it "still fails the compose for a NON-zero account default" do
      template_with("boot_mode" => "uefi_disk")
      account.update!(settings: (account.settings || {}).merge(
        ::Account::DEFAULT_SDWAN_NETWORK_SETTING => 12_345
      ))

      result = service.send(:check_network_declaration, brief)
      expect(result).to include(clarification_needed: true)
      expect(result[:network_declaration_issue]).to include(scope: "account")
    end
  end
end
