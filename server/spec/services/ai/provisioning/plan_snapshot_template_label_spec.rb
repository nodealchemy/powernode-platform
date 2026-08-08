# frozen_string_literal: true

require "rails_helper"

# The approval view must surface the TEMPLATE (IMP 019fe1e0-0b8a, revised).
#
# PlanSnapshotService renders what a human sees at the review_plan gate. It
# derives each row from `skill` + `execution_config.inputs` — count, instance
# type, region — and does NOT use the step's stored `description`. That much is
# sound: the row already reflects the real inputs rather than LLM prose.
#
# What it never showed is the template. `grep template` over the service was
# zero hits. That is the gap that matters, because the template decides
# `boot_mode`, and boot_mode decides whether the provisioned node is a Powernode
# node at all:
#
#   uefi_disk  -> UKI pivot image, carries the agent -> can take module
#                 assignments and complete the runtime handshake
#   cloud_init -> plain cloud image, NO agent -> module assignment and the
#                 DockerHost handshake are unreachable by construction
#
# Observed live 2026-08-08 (platform-autonomy-dryrun P1, plan
# 019fe1db-f680-7116-8e76-110166f070ed): the composer resolved template_id to
# the account's OLDEST template ("base", boot_mode blank => cloud_init) while
# the step prose named "powernode-ops-cell" (uefi_disk). The approver's row read
# "Provision 3× pve.vm.large (dna)" — correct in every field it showed, and
# silent on the one field that made the plan incapable of succeeding.
RSpec.describe Ai::Provisioning::PlanSnapshotService, "template visibility", type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  before { skip "system extension not loaded" unless defined?(::System::NodeTemplate) }

  # NodeTemplate requires a node_platform, so go through the factory.
  let!(:uefi_template) do
    create(:system_node_template, account: account, name: "powernode-ops-cell",
                                  config: { "boot_mode" => "uefi_disk" })
  end

  describe "the extension label resolver" do
    it "resolves a template_id to a label naming the template" do
      resolver = ::Powernode::ExtensionRegistry.provider(:provision_label_resolver)
      skip "no provision_label_resolver registered" unless resolver
      label = resolver.template_label(account: account, inputs: { "template_id" => uefi_template.id })
      expect(label).to include("powernode-ops-cell")
    end

    it "includes boot_mode — the property that decides whether the node gets an agent" do
      resolver = ::Powernode::ExtensionRegistry.provider(:provision_label_resolver)
      skip "no provision_label_resolver registered" unless resolver
      label = resolver.template_label(account: account, inputs: { "template_id" => uefi_template.id })
      expect(label).to match(/uefi_disk/i)
    end

    it "reports a blank boot_mode as cloud_init rather than omitting it" do
      # A blank boot_mode DEFAULTS to cloud_init in ProvisioningService, so
      # showing nothing here would hide exactly the case that bit us.
      # A distinct name: the account fixture set already contains a "base".
      plain = create(:system_node_template, account: account, name: "plain-cloud-image", config: {})
      resolver = ::Powernode::ExtensionRegistry.provider(:provision_label_resolver)
      skip "no provision_label_resolver registered" unless resolver
      label = resolver.template_label(account: account, inputs: { "template_id" => plain.id })
      expect(label).to match(/cloud_init/i)
      expect(label).to include("plain-cloud-image")
    end

    it "returns nil for an absent or unresolvable template_id" do
      resolver = ::Powernode::ExtensionRegistry.provider(:provision_label_resolver)
      skip "no provision_label_resolver registered" unless resolver
      expect(resolver.template_label(account: account, inputs: {})).to be_nil
      expect(resolver.template_label(account: account, inputs: { "template_id" => SecureRandom.uuid })).to be_nil
    end
  end

  describe "core rendering" do
    subject(:service) { described_class.new(account: account) rescue described_class }

    it "core asks the seam for a template label" do
      # Core must not name System::NodeTemplate — it goes through the registry
      # seam, same as instance/region labels.
      src = File.read(Rails.root.join("app/services/ai/provisioning/plan_snapshot_service.rb"))
      expect(src).to include("template_label")
      expect(src).not_to match(/System::NodeTemplate/)
    end
  end
end
