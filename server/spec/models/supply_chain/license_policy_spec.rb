# frozen_string_literal: true

require "rails_helper"

RSpec.describe SupplyChain::LicensePolicy, type: :model do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  describe "associations" do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:created_by).class_name("User").optional }
    it { is_expected.to have_many(:license_violations).class_name("SupplyChain::LicenseViolation").with_foreign_key(:license_policy_id).dependent(:destroy) }
  end

  describe "validations" do
    subject { build(:supply_chain_license_policy, account: account) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_uniqueness_of(:name).scoped_to(:account_id) }
    it { is_expected.to validate_presence_of(:policy_type) }
    it { is_expected.to validate_inclusion_of(:policy_type).in_array(SupplyChain::LicensePolicy::POLICY_TYPES) }
    it { is_expected.to validate_presence_of(:enforcement_level) }
    it { is_expected.to validate_inclusion_of(:enforcement_level).in_array(SupplyChain::LicensePolicy::ENFORCEMENT_LEVELS) }
    it { is_expected.to validate_numericality_of(:priority).is_greater_than_or_equal_to(0) }

    describe "name uniqueness scoped to account" do
      let!(:existing_policy) { create(:supply_chain_license_policy, account: account, name: "Policy A") }

      it "allows duplicate names in different accounts" do
        other_account = create(:account)
        policy = build(:supply_chain_license_policy, account: other_account, name: "Policy A")
        expect(policy).to be_valid
      end

      it "rejects duplicate names in same account" do
        policy = build(:supply_chain_license_policy, account: account, name: "Policy A")
        expect(policy).not_to be_valid
        expect(policy.errors[:name]).to include(/has already been taken/)
      end
    end

    describe "policy_type inclusion" do
      it "accepts all valid policy types" do
        SupplyChain::LicensePolicy::POLICY_TYPES.each do |type|
          policy = build(:supply_chain_license_policy, account: account, policy_type: type)
          expect(policy).to be_valid
        end
      end

      it "rejects invalid policy types" do
        policy = build(:supply_chain_license_policy, account: account, policy_type: "invalid_type")
        expect(policy).not_to be_valid
      end
    end

    describe "enforcement_level inclusion" do
      it "accepts all valid enforcement levels" do
        SupplyChain::LicensePolicy::ENFORCEMENT_LEVELS.each do |level|
          policy = build(:supply_chain_license_policy, account: account, enforcement_level: level)
          expect(policy).to be_valid
        end
      end

      it "rejects invalid enforcement levels" do
        policy = build(:supply_chain_license_policy, account: account, enforcement_level: "invalid_level")
        expect(policy).not_to be_valid
      end
    end
  end

  describe "constants" do
    it "defines POLICY_TYPES" do
      expect(SupplyChain::LicensePolicy::POLICY_TYPES).to eq(%w[allowlist denylist hybrid])
    end

    it "defines ENFORCEMENT_LEVELS" do
      expect(SupplyChain::LicensePolicy::ENFORCEMENT_LEVELS).to eq(%w[log warn block])
    end
  end

  describe "scopes" do
    let!(:active_policy) { create(:supply_chain_license_policy, account: account, is_active: true, name: "Active") }
    let!(:inactive_policy) { create(:supply_chain_license_policy, account: account, is_active: false, name: "Inactive") }
    let!(:default_policy) { create(:supply_chain_license_policy, account: account, is_default: true, name: "Default") }
    let!(:allowlist_policy) { create(:supply_chain_license_policy, account: account, policy_type: "allowlist", name: "Allowlist") }
    let!(:denylist_policy) { create(:supply_chain_license_policy, account: account, policy_type: "denylist", name: "Denylist") }
    let!(:hybrid_policy) { create(:supply_chain_license_policy, account: account, policy_type: "hybrid", name: "Hybrid") }
    let!(:block_policy) { create(:supply_chain_license_policy, account: account, enforcement_level: "block", name: "Block") }
    let!(:warn_policy) { create(:supply_chain_license_policy, account: account, enforcement_level: "warn", name: "Warn") }
    let!(:log_policy) { create(:supply_chain_license_policy, account: account, enforcement_level: "log", name: "Log") }
    let!(:high_priority_policy) { create(:supply_chain_license_policy, account: account, priority: 10, name: "High Priority", created_at: 2.days.ago) }
    let!(:low_priority_policy) { create(:supply_chain_license_policy, account: account, priority: 1, name: "Low Priority", created_at: 1.day.ago) }

    describe ".active" do
      it "returns only active policies" do
        expect(described_class.active).to include(active_policy)
        expect(described_class.active).not_to include(inactive_policy)
      end
    end

    describe ".inactive" do
      it "returns only inactive policies" do
        expect(described_class.inactive).to include(inactive_policy)
        expect(described_class.inactive).not_to include(active_policy)
      end
    end

    describe ".default" do
      it "returns only default policies" do
        expect(described_class.default).to include(default_policy)
        expect(described_class.default).not_to include(active_policy)
      end
    end

    describe ".by_type" do
      it "filters policies by type" do
        expect(described_class.by_type("allowlist")).to include(allowlist_policy)
        expect(described_class.by_type("denylist")).to include(denylist_policy)
        expect(described_class.by_type("hybrid")).to include(hybrid_policy)
      end

      it "excludes other policy types" do
        result = described_class.by_type("allowlist")
        expect(result).not_to include(denylist_policy, hybrid_policy)
      end
    end

    describe ".blocking" do
      it "returns policies with block enforcement level" do
        expect(described_class.blocking).to include(block_policy)
        expect(described_class.blocking).not_to include(warn_policy, log_policy)
      end
    end

    describe ".warning" do
      it "returns policies with warn enforcement level" do
        expect(described_class.warning).to include(warn_policy)
        expect(described_class.warning).not_to include(block_policy, log_policy)
      end
    end

    describe ".ordered" do
      it "orders by priority descending, then created_at ascending" do
        result = described_class.ordered.where(id: [high_priority_policy.id, low_priority_policy.id])
        expect(result.first).to eq(high_priority_policy)
        expect(result.last).to eq(low_priority_policy)
      end
    end
  end

  describe "callbacks" do
    describe "sanitize_jsonb_fields" do
      it "initializes allowed_licenses to empty array if nil" do
        policy = create(:supply_chain_license_policy, account: account, allowed_licenses: nil)
        expect(policy.allowed_licenses).to eq([])
      end

      it "initializes denied_licenses to empty array if nil" do
        policy = create(:supply_chain_license_policy, account: account, denied_licenses: nil)
        expect(policy.denied_licenses).to eq([])
      end

      it "initializes exception_packages to empty array if nil" do
        policy = create(:supply_chain_license_policy, account: account, exception_packages: nil)
        expect(policy.exception_packages).to eq([])
      end

      it "initializes metadata to empty hash if nil" do
        policy = create(:supply_chain_license_policy, account: account, metadata: nil)
        expect(policy.metadata).to eq({})
      end

      it "preserves existing jsonb values" do
        allowed_licenses = %w[MIT Apache-2.0]
        denied_licenses = %w[GPL-3.0-only]
        exception_packages = [{ "package" => "test", "license" => "MIT", "reason" => "test" }]
        metadata = { "key" => "value" }
        policy = create(:supply_chain_license_policy,
                       account: account,
                       allowed_licenses: allowed_licenses,
                       denied_licenses: denied_licenses,
                       exception_packages: exception_packages,
                       metadata: metadata)
        expect(policy.allowed_licenses).to eq(allowed_licenses)
        expect(policy.denied_licenses).to eq(denied_licenses)
        expect(policy.exception_packages).to eq(exception_packages)
        expect(policy.metadata).to eq(metadata)
      end
    end

    describe "ensure_single_default" do
      let!(:existing_default) { create(:supply_chain_license_policy, account: account, is_default: true, name: "Existing Default") }

      it "unsets other default policies when setting a new default" do
        new_policy = create(:supply_chain_license_policy, account: account, is_default: false, name: "New Policy")
        new_policy.update!(is_default: true)

        expect(new_policy.reload.is_default).to be true
        expect(existing_default.reload.is_default).to be false
      end

      it "does not affect other accounts" do
        other_account = create(:account)
        other_default = create(:supply_chain_license_policy, account: other_account, is_default: true, name: "Other Default")

        new_policy = create(:supply_chain_license_policy, account: account, is_default: true, name: "New Default")

        expect(new_policy.reload.is_default).to be true
        expect(existing_default.reload.is_default).to be false
        expect(other_default.reload.is_default).to be true
      end

      it "does not trigger when is_default is not changed" do
        policy = create(:supply_chain_license_policy, account: account, is_default: false, name: "Test")
        policy.update!(name: "Updated Name")

        expect(existing_default.reload.is_default).to be true
      end
    end
  end

  describe "class methods" do
    describe ".default_for_account" do
      context "when a default policy exists" do
        let!(:default_policy) { create(:supply_chain_license_policy, account: account, is_default: true, priority: 5) }
        let!(:other_policy) { create(:supply_chain_license_policy, account: account, is_active: true, priority: 10) }

        it "returns the default policy" do
          expect(described_class.default_for_account(account)).to eq(default_policy)
        end
      end

      context "when no default policy exists" do
        let!(:high_priority) { create(:supply_chain_license_policy, account: account, is_active: true, priority: 10) }
        let!(:low_priority) { create(:supply_chain_license_policy, account: account, is_active: true, priority: 5) }

        it "returns the highest priority active policy" do
          expect(described_class.default_for_account(account)).to eq(high_priority)
        end
      end

      context "when no policies exist" do
        it "returns nil" do
          expect(described_class.default_for_account(account)).to be_nil
        end
      end
    end
  end

  describe "predicate methods" do
    describe "#active?" do
      it "returns true when is_active is true" do
        policy = build(:supply_chain_license_policy, is_active: true)
        expect(policy.active?).to be true
      end

      it "returns false when is_active is false" do
        policy = build(:supply_chain_license_policy, is_active: false)
        expect(policy.active?).to be false
      end
    end

    describe "#default?" do
      it "returns true when is_default is true" do
        policy = build(:supply_chain_license_policy, is_default: true)
        expect(policy.default?).to be true
      end

      it "returns false when is_default is false" do
        policy = build(:supply_chain_license_policy, is_default: false)
        expect(policy.default?).to be false
      end
    end

    describe "#allowlist?" do
      it "returns true when policy_type is allowlist" do
        policy = build(:supply_chain_license_policy, policy_type: "allowlist")
        expect(policy.allowlist?).to be true
      end

      it "returns false for other policy types" do
        policy = build(:supply_chain_license_policy, policy_type: "denylist")
        expect(policy.allowlist?).to be false
      end
    end

    describe "#denylist?" do
      it "returns true when policy_type is denylist" do
        policy = build(:supply_chain_license_policy, policy_type: "denylist")
        expect(policy.denylist?).to be true
      end

      it "returns false for other policy types" do
        policy = build(:supply_chain_license_policy, policy_type: "allowlist")
        expect(policy.denylist?).to be false
      end
    end

    describe "#hybrid?" do
      it "returns true when policy_type is hybrid" do
        policy = build(:supply_chain_license_policy, policy_type: "hybrid")
        expect(policy.hybrid?).to be true
      end

      it "returns false for other policy types" do
        policy = build(:supply_chain_license_policy, policy_type: "allowlist")
        expect(policy.hybrid?).to be false
      end
    end

    describe "#blocking?" do
      it "returns true when enforcement_level is block" do
        policy = build(:supply_chain_license_policy, enforcement_level: "block")
        expect(policy.blocking?).to be true
      end

      it "returns false for other enforcement levels" do
        policy = build(:supply_chain_license_policy, enforcement_level: "warn")
        expect(policy.blocking?).to be false
      end
    end

    describe "#warning?" do
      it "returns true when enforcement_level is warn" do
        policy = build(:supply_chain_license_policy, enforcement_level: "warn")
        expect(policy.warning?).to be true
      end

      it "returns false for other enforcement levels" do
        policy = build(:supply_chain_license_policy, enforcement_level: "block")
        expect(policy.warning?).to be false
      end
    end

    describe "#logging?" do
      it "returns true when enforcement_level is log" do
        policy = build(:supply_chain_license_policy, enforcement_level: "log")
        expect(policy.logging?).to be true
      end

      it "returns false for other enforcement levels" do
        policy = build(:supply_chain_license_policy, enforcement_level: "warn")
        expect(policy.logging?).to be false
      end
    end
  end

  describe "activation methods" do
    describe "#activate!" do
      it "sets is_active to true" do
        policy = create(:supply_chain_license_policy, account: account, is_active: false)
        policy.activate!
        expect(policy.reload.is_active).to be true
      end
    end

    describe "#deactivate!" do
      it "sets is_active to false" do
        policy = create(:supply_chain_license_policy, account: account, is_active: true)
        policy.deactivate!
        expect(policy.reload.is_active).to be false
      end
    end

    describe "#set_as_default!" do
      let!(:existing_default) { create(:supply_chain_license_policy, account: account, is_default: true, name: "Existing") }
      let(:policy) { create(:supply_chain_license_policy, account: account, is_default: false, name: "New") }

      it "sets the policy as default" do
        policy.set_as_default!
        expect(policy.reload.is_default).to be true
      end

      it "unsets other default policies in the same account" do
        policy.set_as_default!
        expect(existing_default.reload.is_default).to be false
      end

      it "uses a transaction" do
        expect(policy).to receive(:transaction).and_call_original
        policy.set_as_default!
      end
    end
  end

  describe "license management methods" do
    let(:policy) { create(:supply_chain_license_policy, account: account) }

    describe "#allowed_license?" do
      context "when license is in denied list" do
        before { policy.update!(denied_licenses: ["GPL-3.0-only"]) }

        it "returns false" do
          expect(policy.allowed_license?("GPL-3.0-only")).to be false
        end
      end

      context "when allowed_licenses is blank" do
        before { policy.update!(allowed_licenses: []) }

        it "returns true for any license not in denied list" do
          expect(policy.allowed_license?("MIT")).to be true
        end
      end

      context "when allowed_licenses is populated" do
        before { policy.update!(allowed_licenses: ["MIT", "Apache-2.0"]) }

        it "returns true for licenses in allowlist" do
          expect(policy.allowed_license?("MIT")).to be true
          expect(policy.allowed_license?("Apache-2.0")).to be true
        end

        it "returns false for licenses not in allowlist" do
          expect(policy.allowed_license?("GPL-3.0-only")).to be false
        end
      end
    end

    describe "#denied_license?" do
      before { policy.update!(denied_licenses: ["GPL-3.0-only", "AGPL-3.0-only"]) }

      it "returns true for licenses in denylist" do
        expect(policy.denied_license?("GPL-3.0-only")).to be true
        expect(policy.denied_license?("AGPL-3.0-only")).to be true
      end

      it "returns false for licenses not in denylist" do
        expect(policy.denied_license?("MIT")).to be false
      end
    end

    describe "#add_allowed_license" do
      it "adds a license to the allowed list" do
        policy.add_allowed_license("MIT")
        expect(policy.reload.allowed_licenses).to include("MIT")
      end

      it "prevents duplicates" do
        policy.update!(allowed_licenses: ["MIT"])
        policy.add_allowed_license("MIT")
        expect(policy.reload.allowed_licenses.count("MIT")).to eq(1)
      end
    end

    describe "#remove_allowed_license" do
      before { policy.update!(allowed_licenses: ["MIT", "Apache-2.0"]) }

      it "removes a license from the allowed list" do
        policy.remove_allowed_license("MIT")
        expect(policy.reload.allowed_licenses).not_to include("MIT")
        expect(policy.reload.allowed_licenses).to include("Apache-2.0")
      end
    end

    describe "#add_denied_license" do
      it "adds a license to the denied list" do
        policy.add_denied_license("GPL-3.0-only")
        expect(policy.reload.denied_licenses).to include("GPL-3.0-only")
      end

      it "prevents duplicates" do
        policy.update!(denied_licenses: ["GPL-3.0-only"])
        policy.add_denied_license("GPL-3.0-only")
        expect(policy.reload.denied_licenses.count("GPL-3.0-only")).to eq(1)
      end
    end

    describe "#remove_denied_license" do
      before { policy.update!(denied_licenses: ["GPL-3.0-only", "AGPL-3.0-only"]) }

      it "removes a license from the denied list" do
        policy.remove_denied_license("GPL-3.0-only")
        expect(policy.reload.denied_licenses).not_to include("GPL-3.0-only")
        expect(policy.reload.denied_licenses).to include("AGPL-3.0-only")
      end
    end
  end

  describe "exception management methods" do
    let(:policy) { create(:supply_chain_license_policy, account: account) }

    describe "#exception_for_license?" do
      before do
        policy.update!(exception_packages: [
          { "package" => "test-package", "license" => "MIT", "reason" => "test" }
        ])
      end

      it "returns true when an exception exists for the license" do
        expect(policy.exception_for_license?("MIT")).to be true
      end

      it "returns false when no exception exists for the license" do
        expect(policy.exception_for_license?("Apache-2.0")).to be false
      end
    end

    describe "#exception_for_package?" do
      before do
        policy.update!(exception_packages: [
          { "package" => "test-package", "license" => "MIT", "reason" => "test" }
        ])
      end

      it "returns true when an exception exists for the package" do
        expect(policy.exception_for_package?("test-package")).to be true
      end

      it "returns false when no exception exists for the package" do
        expect(policy.exception_for_package?("other-package")).to be false
      end
    end

    describe "#add_exception" do
      it "adds an exception with all required fields" do
        expires_at = 30.days.from_now
        policy.add_exception(
          package_name: "test-package",
          license: "GPL-3.0-only",
          reason: "Legacy dependency",
          expires_at: expires_at
        )

        exception = policy.reload.exception_packages.first
        expect(exception["package"]).to eq("test-package")
        expect(exception["license"]).to eq("GPL-3.0-only")
        expect(exception["reason"]).to eq("Legacy dependency")
        expect(exception["added_at"]).to be_present
        expect(exception["expires_at"]).to be_present
      end

      it "adds an exception without expiration" do
        policy.add_exception(
          package_name: "test-package",
          license: "GPL-3.0-only",
          reason: "Legacy dependency"
        )

        exception = policy.reload.exception_packages.first
        expect(exception["expires_at"]).to be_nil
      end

      it "allows multiple exceptions" do
        policy.add_exception(package_name: "pkg1", license: "MIT", reason: "test1")
        policy.add_exception(package_name: "pkg2", license: "Apache-2.0", reason: "test2")

        expect(policy.reload.exception_packages.length).to eq(2)
      end
    end

    describe "#remove_exception" do
      before do
        policy.update!(exception_packages: [
          { "package" => "pkg1", "license" => "MIT", "reason" => "test1" },
          { "package" => "pkg2", "license" => "Apache-2.0", "reason" => "test2" }
        ])
      end

      it "removes the exception for the specified package" do
        policy.remove_exception("pkg1")
        exceptions = policy.reload.exception_packages
        expect(exceptions.length).to eq(1)
        expect(exceptions.first["package"]).to eq("pkg2")
      end

      it "does not affect other exceptions" do
        policy.remove_exception("pkg1")
        expect(policy.reload.exception_packages.any? { |e| e["package"] == "pkg2" }).to be true
      end
    end
  end

  describe "#evaluate" do
    let(:policy) { create(:supply_chain_license_policy, account: account, name: "Test Policy", enforcement_level: "block") }

    describe "basic result structure" do
      it "returns a hash with all required fields" do
        result = policy.evaluate("MIT")
        expect(result).to include(
          policy_id: policy.id,
          policy_name: "Test Policy",
          license_spdx_id: "MIT",
          enforcement_level: "block",
          compliant: true,
          violations: []
        )
      end
    end

    describe "when license_spdx_id is blank" do
      it "returns compliant with reason" do
        result = policy.evaluate(nil)
        expect(result[:compliant]).to be true
        expect(result[:reason]).to eq("No license specified")
      end

      it "works with empty string" do
        result = policy.evaluate("")
        expect(result[:compliant]).to be true
        expect(result[:reason]).to eq("No license specified")
      end
    end

    describe "exception handling" do
      before do
        policy.update!(
          policy_type: "denylist",
          denied_licenses: ["GPL-3.0-only"],
          exception_packages: [
            { "package" => "test-pkg", "license" => "GPL-3.0-only", "reason" => "Required" }
          ]
        )
      end

      it "returns compliant when license has an exception" do
        result = policy.evaluate("GPL-3.0-only")
        expect(result[:compliant]).to be true
      end
    end

    describe "allowlist policy" do
      let!(:mit_license) { create(:supply_chain_license, :permissive, spdx_id: "MIT") }
      let!(:gpl_license) { create(:supply_chain_license, :copyleft, spdx_id: "GPL-3.0-only") }

      before do
        policy.update!(
          policy_type: "allowlist",
          allowed_licenses: ["MIT", "Apache-2.0"]
        )
      end

      it "marks as compliant when license is in allowlist" do
        result = policy.evaluate("MIT")
        expect(result[:compliant]).to be true
        expect(result[:violations]).to be_empty
      end

      it "marks as non-compliant when license is not in allowlist" do
        result = policy.evaluate("GPL-3.0-only")
        expect(result[:compliant]).to be false
        expect(result[:violations]).to include(
          hash_including(
            type: "not_allowed",
            message: "License 'GPL-3.0-only' is not in the allowlist"
          )
        )
      end

      it "marks as compliant when allowlist is empty" do
        policy.update!(allowed_licenses: [])
        result = policy.evaluate("GPL-3.0-only")
        expect(result[:compliant]).to be true
      end
    end

    describe "denylist policy" do
      let!(:mit_license) { create(:supply_chain_license, :permissive, spdx_id: "MIT") }
      let!(:gpl_license) { create(:supply_chain_license, :copyleft, spdx_id: "GPL-3.0-only") }

      before do
        policy.update!(
          policy_type: "denylist",
          denied_licenses: ["GPL-3.0-only", "AGPL-3.0-only"]
        )
      end

      it "marks as compliant when license is not in denylist" do
        result = policy.evaluate("MIT")
        expect(result[:compliant]).to be true
        expect(result[:violations]).to be_empty
      end

      it "marks as non-compliant when license is in denylist" do
        result = policy.evaluate("GPL-3.0-only")
        expect(result[:compliant]).to be false
        expect(result[:violations]).to include(
          hash_including(
            type: "denied",
            message: "License 'GPL-3.0-only' is explicitly denied"
          )
        )
      end
    end

    describe "hybrid policy" do
      let!(:mit_license) { create(:supply_chain_license, :permissive, spdx_id: "MIT") }
      let!(:apache_license) { create(:supply_chain_license, :permissive, spdx_id: "Apache-2.0") }
      let!(:gpl_license) { create(:supply_chain_license, :copyleft, spdx_id: "GPL-3.0-only") }

      before do
        policy.update!(
          policy_type: "hybrid",
          allowed_licenses: ["MIT", "Apache-2.0"],
          denied_licenses: ["GPL-3.0-only"]
        )
      end

      it "marks as compliant when license is in allowlist and not in denylist" do
        result = policy.evaluate("MIT")
        expect(result[:compliant]).to be true
      end

      it "marks as non-compliant when license is in denylist" do
        result = policy.evaluate("GPL-3.0-only")
        expect(result[:compliant]).to be false
        expect(result[:violations]).to include(
          hash_including(type: "denied")
        )
      end

      it "marks as non-compliant when license is not in allowlist" do
        result = policy.evaluate("BSD-3-Clause")
        expect(result[:compliant]).to be false
        expect(result[:violations]).to include(
          hash_including(type: "not_allowed")
        )
      end

      context "when allowlist is empty" do
        before { policy.update!(allowed_licenses: []) }

        it "only checks denylist" do
          result = policy.evaluate("MIT")
          expect(result[:compliant]).to be true
        end
      end
    end

    describe "copyleft checking" do
      let!(:mit_license) { create(:supply_chain_license, :permissive, spdx_id: "MIT", is_copyleft: false) }
      let!(:lgpl_license) do
        create(:supply_chain_license,
               spdx_id: "LGPL-3.0",
               category: "weak_copyleft",
               is_copyleft: true,
               is_strong_copyleft: false)
      end
      let!(:gpl_license) { create(:supply_chain_license, :copyleft, spdx_id: "GPL-3.0-only", is_strong_copyleft: true) }

      context "when block_copyleft is enabled" do
        before { policy.update!(policy_type: "allowlist", block_copyleft: true) }

        it "blocks all copyleft licenses" do
          result = policy.evaluate("LGPL-3.0")
          expect(result[:compliant]).to be false
          expect(result[:violations]).to include(
            hash_including(
              type: "copyleft",
              message: "Copyleft licenses are blocked by this policy"
            )
          )
        end

        it "allows non-copyleft licenses" do
          result = policy.evaluate("MIT")
          expect(result[:compliant]).to be true
        end
      end

      context "when block_strong_copyleft is enabled" do
        before { policy.update!(policy_type: "allowlist", block_strong_copyleft: true) }

        it "blocks strong copyleft licenses" do
          result = policy.evaluate("GPL-3.0-only")
          expect(result[:compliant]).to be false
          expect(result[:violations]).to include(
            hash_including(
              type: "strong_copyleft",
              message: "Strong copyleft licenses are blocked by this policy"
            )
          )
        end

        it "allows weak copyleft licenses" do
          result = policy.evaluate("LGPL-3.0")
          expect(result[:compliant]).to be true
        end
      end

      context "when block_unknown is enabled" do
        let!(:unknown_license) { create(:supply_chain_license, spdx_id: "Unknown", category: "unknown") }

        before { policy.update!(policy_type: "allowlist", block_unknown: true) }

        it "blocks unknown licenses" do
          result = policy.evaluate("Unknown")
          expect(result[:compliant]).to be false
          expect(result[:violations]).to include(
            hash_including(
              type: "unknown",
              message: "Unknown licenses are blocked by this policy"
            )
          )
        end
      end
    end
  end

  describe "#evaluate_component" do
    let(:policy) { create(:supply_chain_license_policy, account: account) }
    let(:component) { build(:supply_chain_sbom_component, license_spdx_id: "MIT", license_name: "MIT License") }

    it "evaluates using license_spdx_id when present" do
      expect(policy).to receive(:evaluate).with("MIT")
      policy.evaluate_component(component)
    end

    it "falls back to license_name when license_spdx_id is nil" do
      component.license_spdx_id = nil
      expect(policy).to receive(:evaluate).with("MIT License")
      policy.evaluate_component(component)
    end
  end

  describe "#summary" do
    let(:policy) do
      create(:supply_chain_license_policy,
             account: account,
             name: "Test Policy",
             description: "Test description",
             policy_type: "hybrid",
             enforcement_level: "block",
             is_active: true,
             is_default: false,
             priority: 5,
             allowed_licenses: ["MIT", "Apache-2.0"],
             denied_licenses: ["GPL-3.0-only"],
             exception_packages: [{ "package" => "test", "license" => "MIT", "reason" => "test" }],
             block_copyleft: true,
             block_strong_copyleft: false,
             block_unknown: true)
    end

    it "returns a hash with policy details" do
      summary = policy.summary
      expect(summary).to be_a(Hash)
      expect(summary[:id]).to eq(policy.id)
      expect(summary[:name]).to eq("Test Policy")
      expect(summary[:description]).to eq("Test description")
      expect(summary[:policy_type]).to eq("hybrid")
      expect(summary[:enforcement_level]).to eq("block")
      expect(summary[:is_active]).to be true
      expect(summary[:is_default]).to be false
      expect(summary[:priority]).to eq(5)
      expect(summary[:allowed_license_count]).to eq(2)
      expect(summary[:denied_license_count]).to eq(1)
      expect(summary[:exception_count]).to eq(1)
      expect(summary[:block_copyleft]).to be true
      expect(summary[:block_strong_copyleft]).to be false
      expect(summary[:block_unknown]).to be true
      expect(summary[:created_at]).to eq(policy.created_at)
    end
  end

  describe "Auditable concern" do
    it "includes Auditable module" do
      expect(described_class.ancestors).to include(Auditable)
    end

    it "has auditable_attributes method (private)" do
      policy = build(:supply_chain_license_policy, account: account)
      expect(policy.send(:auditable_attributes)).to be_a(Hash)
    end
  end
end
