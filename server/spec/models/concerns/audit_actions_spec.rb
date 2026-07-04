# frozen_string_literal: true

require "rails_helper"

# Regression coverage for the AuditActions extension-registration seam
# (server/app/models/concerns/audit_actions.rb): the mechanism that lets an
# extension register its own audit action/source tokens into the dynamic
# AuditActions.all_actions / all_sources union without core naming the
# extension. Uses a synthetic "acme_ext" namespace throughout — core specs
# stay extension-agnostic; specs that assert on a REAL extension's tokens
# live in that extension's own spec/lib (see extensions/system/server/spec/
# lib/powernode_system/audit_actions_registration_spec.rb and the
# supply-chain sibling).
RSpec.describe AuditActions do
  # @extension_actions / @extension_sources are process-global class ivars,
  # populated once at boot by every currently-loaded extension's engine
  # initializer (supply_chain, system, and — in full/private mode —
  # business). Snapshot and restore around every example so this spec's
  # synthetic registrations never leak into other specs, and so it never
  # clobbers the real registrations this process already booted with.
  around do |example|
    original_actions = described_class.extension_actions.dup
    original_sources = described_class.extension_sources.dup
    example.run
  ensure
    described_class.instance_variable_set(:@extension_actions, original_actions)
    described_class.instance_variable_set(:@extension_sources, original_sources)
  end

  describe ".register_actions" do
    it "adds the namespace's actions to the dynamic union" do
      expect(described_class.valid_action?("acme_ext.widgets.create")).to be false

      described_class.register_actions("acme_ext", %w[acme_ext.widgets.create acme_ext.widgets.delete])

      expect(described_class.valid_action?("acme_ext.widgets.create")).to be true
      expect(described_class.all_actions).to include("acme_ext.widgets.create", "acme_ext.widgets.delete")
    end

    it "is idempotent per namespace — re-registering replaces rather than accumulates" do
      described_class.register_actions("acme_ext", %w[acme_ext.a])
      described_class.register_actions("acme_ext", %w[acme_ext.a acme_ext.b])

      expect(described_class.extension_actions["acme_ext"]).to contain_exactly("acme_ext.a", "acme_ext.b")
      expect(described_class.all_actions.count("acme_ext.a")).to eq(1)
    end

    it "leaves an unregistered/typo action invalid" do
      described_class.register_actions("acme_ext", %w[acme_ext.widgets.create])

      expect(described_class.valid_action?("acme_ext.widgets.craete")).to be false
    end

    it "never widens or narrows core's own actions" do
      expect(described_class.valid_action?("create")).to be true

      described_class.register_actions("acme_ext", %w[acme_ext.widgets.create])

      expect(described_class.valid_action?("create")).to be true
      expect(described_class::CORE_ALL_ACTIONS).not_to include("acme_ext.widgets.create")
    end
  end

  describe ".register_sources" do
    it "unions source tokens idempotently across calls" do
      expect(described_class.valid_source?("acme_ext_source")).to be false

      described_class.register_sources(%w[acme_ext_source])
      expect(described_class.valid_source?("acme_ext_source")).to be true

      described_class.register_sources(%w[acme_ext_source other_source])
      expect(described_class.all_sources.count("acme_ext_source")).to eq(1)
      expect(described_class.valid_source?("other_source")).to be true
    end
  end

  describe "AuditLog integration" do
    let(:account) { create(:account) }
    let(:user) { create(:user, account: account) }

    it "persists an AuditLog whose action was registered by an extension" do
      described_class.register_actions("acme_ext", %w[acme_ext.widgets.create])

      audit_log = build(:audit_log, account: account, user: user, action: "acme_ext.widgets.create")

      expect { audit_log.save! }.not_to raise_error
      expect(AuditLog.find(audit_log.id).action).to eq("acme_ext.widgets.create")
    end

    it "raises for an action that is neither core nor registered by any extension" do
      audit_log = build(:audit_log, account: account, user: user, action: "acme_ext.widgets.unregistered_typo")

      expect { audit_log.save! }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end
end
