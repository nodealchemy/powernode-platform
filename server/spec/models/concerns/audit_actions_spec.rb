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

  describe "no legacy support (IMP-85fb47438be6)" do
    # inherit: false — the plain one-arg form also resolves top-level
    # constants (Object::LEGACY_ACTIONS, if one ever existed), which is not
    # what this is pinning (F9, review 2026-09-17).
    it "does not define LEGACY_ACTIONS" do
      expect(described_class.const_defined?(:LEGACY_ACTIONS, false)).to be false
    end

    it "does not define MIGRATION_MAPPINGS" do
      expect(described_class.const_defined?(:MIGRATION_MAPPINGS, false)).to be false
    end

    it "does not respond to standardize_action" do
      expect(described_class).not_to respond_to(:standardize_action)
      expect(AuditLog).not_to respond_to(:standardize_action)
    end

    # No carve-out: AI_AGENT_TEAM_ACTIONS was renamed to the dot convention
    # (ai.agent_team.*) specifically so this holds with no exception constant
    # (operator decision 2026-09-17, superseding an earlier KNOWN_LEGACY_
    # SHAPED_EXCEPTIONS carve-out this spec used to need).
    it "has no core action token matching the legacy ai_<domain>.<verb> alias shape" do
      offenders = described_class::CORE_ALL_ACTIONS
        .select { |token| token.match?(described_class::LEGACY_ALIAS_PATTERN) }

      expect(offenders).to be_empty
    end

    # Uses the SAME dot_underscore_sibling the production guard uses (F3,
    # review 2026-09-17) — one rule, not a second hand-written copy that could
    # drift from what register_actions actually enforces.
    it "has no underscore/dot sibling pairs among core action tokens" do
      all = described_class::CORE_ALL_ACTIONS
      pairs = all.select { |token| (sibling = described_class.dot_underscore_sibling(token)) && all.include?(sibling) }

      expect(pairs).to be_empty
    end

    it "register_actions raises for a token matching the legacy alias shape" do
      expect {
        described_class.register_actions("acme_ext", %w[ai_widgets.create])
      }.to raise_error(ArgumentError, /legacy-shaped/)

      expect(described_class.valid_action?("ai_widgets.create")).to be false
    end

    it "register_actions raises for a token that is the dotted sibling of an existing flat core action" do
      expect {
        described_class.register_actions("acme_ext", %w[subscription.change])
      }.to raise_error(ArgumentError, /underscore\/dot sibling/)

      expect(described_class.valid_action?("subscription.change")).to be false
    end

    # F3: a token with neither "." nor "_" (so its "sibling" transform is a
    # no-op) must not be treated as colliding with itself. Before the fix,
    # registering the literal string "payment" (already a valid core action)
    # raised — which would have aborted supply-chain's extension boot
    # (its engine has no rescue around this call) and, for system's engine
    # (which does rescue and warn), silently dropped its entire audit action
    # set, after which every system.* audit write would fail validation.
    it "register_actions does not raise for a token that only collides with itself" do
      expect(described_class.valid_action?("payment")).to be true

      expect {
        described_class.register_actions("acme_ext", %w[payment])
      }.not_to raise_error

      expect(described_class.extension_actions["acme_ext"]).to contain_exactly("payment")
    end

    it "register_actions does not partially register a namespace that fails validation" do
      described_class.register_actions("acme_ext", %w[acme_ext.safe_token])
      expect {
        described_class.register_actions("acme_ext", %w[acme_ext.safe_token ai_widgets.create])
      }.to raise_error(ArgumentError)

      expect(described_class.extension_actions["acme_ext"]).to contain_exactly("acme_ext.safe_token")
    end
  end

  describe "REPORT_REQUEST_ACTIONS" do
    it "matches ReportRequest's status-derived action names plus the cleanup action" do
      inclusion_validator = ReportRequest.validators_on(:status)
        .find { |v| v.is_a?(ActiveModel::Validations::InclusionValidator) }
      statuses = inclusion_validator.options[:in]

      expected = statuses.map { |status| "report_request_#{status}" } + %w[report_request_cleanup_deleted]

      expect(described_class::REPORT_REQUEST_ACTIONS).to match_array(expected)
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
