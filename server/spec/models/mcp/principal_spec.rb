# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mcp::Principal do
  # Save/restore the (boot-injected) resolvers so per-example overrides don't
  # clobber them for the rest of the suite.
  around do |example|
    orig_instance = described_class.instance_resolver
    orig_grant = described_class.tool_grant_resolver
    example.run
    described_class.instance_resolver = orig_instance
    described_class.tool_grant_resolver = orig_grant
  end

  describe ".for_user" do
    it "wraps a User principal with an unrestricted catalog scope" do
      account = create(:account)
      user = create(:user, account: account)

      p = described_class.for_user(user)

      expect(p.user?).to be(true)
      expect(p.instance?).to be(false)
      expect(p.account).to eq(account)
      expect(p.user).to eq(user)
      expect(p.node_instance).to be_nil
      expect(p.subject_id).to eq(user.id)
      expect(p.capability_scope).to be_nil
    end
  end

  describe ".for_instance_cn" do
    let(:account) { create(:account) }
    let(:fake_instance) do
      instance_double("NodeInstance", id: "inst-1", account: account, declared_capabilities: %w[system.read fleet.read])
    end

    it "resolves a CN to an instance principal via the injected resolver" do
      described_class.instance_resolver = ->(cn) { cn == "inst-1" ? fake_instance : nil }

      p = described_class.for_instance_cn("inst-1")

      expect(p.instance?).to be(true)
      expect(p.user?).to be(false)
      expect(p.account).to eq(account)
      expect(p.node_instance).to eq(fake_instance)
      expect(p.subject_id).to eq("inst-1")
      expect(p.capability_scope).to eq(%w[system.read fleet.read])
    end

    it "scopes to an empty capability set when the instance declares none (default-deny)" do
      bare = instance_double("NodeInstance", id: "inst-2", account: account, declared_capabilities: nil)
      described_class.instance_resolver = ->(_cn) { bare }
      expect(described_class.for_instance_cn("inst-2").capability_scope).to eq([])
    end

    it "returns nil when the CN does not resolve" do
      described_class.instance_resolver = ->(_cn) { nil }
      expect(described_class.for_instance_cn("nope")).to be_nil
    end

    it "fails closed when no resolver is injected (stock core)" do
      expect(described_class.for_instance_cn("anything")).to be_nil
    end
  end

  describe "tool authorization (default-deny for instances)" do
    let(:account) { create(:account) }
    let(:inst) { instance_double("NodeInstance", id: "i1", account: account, declared_capabilities: []) }

    before { described_class.instance_resolver = ->(_cn) { inst } }

    it "users may invoke any tool (unrestricted)" do
      p = described_class.for_user(create(:user, account: account))
      expect(p.may_invoke?("platform.system_destroy_instance")).to be(true)
    end

    it "instances are default-deny with no grant" do
      described_class.tool_grant_resolver = ->(_i) { [] }
      p = described_class.for_instance_cn("i1")
      expect(p.may_invoke?("platform.health")).to be(false)
      expect(p.filter_tools([{ "name" => "platform.health" }])).to eq([])
    end

    it "instances may invoke tools matching a granted glob pattern" do
      described_class.tool_grant_resolver = ->(_i) { %w[platform.system_*_read platform.health] }
      p = described_class.for_instance_cn("i1")
      expect(p.may_invoke?("platform.system_list_instances_read")).to be(true)
      expect(p.may_invoke?("platform.health")).to be(true)
      expect(p.may_invoke?("platform.system_destroy_instance")).to be(false)
      kept = p.filter_tools([{ "name" => "platform.health" }, { "name" => "platform.system_destroy_instance" }])
      expect(kept.map { |t| t["name"] }).to eq(%w[platform.health])
    end
  end

  describe ".for_federation_partner" do
    let(:account) { create(:account) }
    let(:partner) do
      create(:federation_partner, :active, account: account,
                                            allowed_capabilities: [ "platform.system_list_*", "platform.health" ])
    end
    subject(:principal) { described_class.for_federation_partner(partner) }

    it "is a default-deny federation principal bound to the partner's local account" do
      expect(principal.federation?).to be true
      expect(principal.restricted?).to be true
      expect(principal.user?).to be false
      expect(principal.account).to eq(account)
      expect(principal.subject_id).to eq(partner.id)
    end

    it "may invoke only tools matching allowed_capabilities" do
      expect(principal.may_invoke?("platform.system_list_templates")).to be true
      expect(principal.may_invoke?("platform.health")).to be true
      expect(principal.may_invoke?("platform.kb_publish")).to be false
    end

    it "never invokes a destroy-shaped tool, even when allowed_capabilities would match" do
      p = described_class.for_federation_partner(
        create(:federation_partner, :active, account: account, allowed_capabilities: [ "platform.system_*" ])
      )
      expect(p.may_invoke?("platform.system_list_templates")).to be true
      expect(p.may_invoke?("platform.system_terminate_instance")).to be false
      expect(p.may_invoke?("platform.system_reboot_instance")).to be false
    end

    it "filters a catalog to the granted, non-destructive subset" do
      kept = principal.filter_tools([
        { "name" => "platform.system_list_templates" },
        { "name" => "platform.kb_publish" },
        { "name" => "platform.system_destroy_instance" }
      ])
      expect(kept.map { |t| t["name"] }).to eq(%w[platform.system_list_templates])
    end

    it "exposes allowed_capabilities as its capability_scope" do
      expect(principal.capability_scope).to eq([ "platform.system_list_*", "platform.health" ])
    end
  end
end
