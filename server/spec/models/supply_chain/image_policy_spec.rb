# frozen_string_literal: true

require "rails_helper"

RSpec.describe SupplyChain::ImagePolicy, type: :model do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  describe "associations" do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:created_by).class_name("User").optional }
  end

  describe "validations" do
    subject { build(:supply_chain_image_policy, account: account) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_uniqueness_of(:name).scoped_to(:account_id) }
    it { is_expected.to validate_presence_of(:policy_type) }
    it { is_expected.to validate_inclusion_of(:policy_type).in_array(SupplyChain::ImagePolicy::POLICY_TYPES) }
    it { is_expected.to validate_presence_of(:enforcement_level) }
    it { is_expected.to validate_inclusion_of(:enforcement_level).in_array(SupplyChain::ImagePolicy::ENFORCEMENT_LEVELS) }
    it { is_expected.to validate_numericality_of(:priority).is_greater_than_or_equal_to(0) }
    it { is_expected.to validate_numericality_of(:max_critical_vulns).is_greater_than_or_equal_to(0).allow_nil }
    it { is_expected.to validate_numericality_of(:max_high_vulns).is_greater_than_or_equal_to(0).allow_nil }

    describe "name uniqueness scoped to account" do
      let!(:existing_policy) { create(:supply_chain_image_policy, account: account, name: "Policy A") }

      it "allows duplicate names in different accounts" do
        other_account = create(:account)
        policy = build(:supply_chain_image_policy, account: other_account, name: "Policy A")
        expect(policy).to be_valid
      end

      it "rejects duplicate names in same account" do
        policy = build(:supply_chain_image_policy, account: account, name: "Policy A")
        expect(policy).not_to be_valid
        expect(policy.errors[:name]).to include(/has already been taken/)
      end
    end

    describe "policy_type inclusion" do
      it "accepts all valid policy types" do
        SupplyChain::ImagePolicy::POLICY_TYPES.each do |type|
          policy = build(:supply_chain_image_policy, account: account, policy_type: type)
          expect(policy).to be_valid
        end
      end

      it "rejects invalid policy types" do
        policy = build(:supply_chain_image_policy, account: account, policy_type: "invalid_type")
        expect(policy).not_to be_valid
      end
    end

    describe "enforcement_level inclusion" do
      it "accepts all valid enforcement levels" do
        SupplyChain::ImagePolicy::ENFORCEMENT_LEVELS.each do |level|
          policy = build(:supply_chain_image_policy, account: account, enforcement_level: level)
          expect(policy).to be_valid
        end
      end

      it "rejects invalid enforcement levels" do
        policy = build(:supply_chain_image_policy, account: account, enforcement_level: "invalid_level")
        expect(policy).not_to be_valid
      end
    end
  end

  describe "constants" do
    it "defines POLICY_TYPES" do
      expect(SupplyChain::ImagePolicy::POLICY_TYPES).to eq(%w[registry_allowlist signature_required vulnerability_threshold custom])
    end

    it "defines ENFORCEMENT_LEVELS" do
      expect(SupplyChain::ImagePolicy::ENFORCEMENT_LEVELS).to eq(%w[log warn block])
    end
  end

  describe "scopes" do
    let!(:active_policy) { create(:supply_chain_image_policy, account: account, is_active: true, name: "Active") }
    let!(:inactive_policy) { create(:supply_chain_image_policy, account: account, is_active: false, name: "Inactive") }
    let!(:registry_policy) { create(:supply_chain_image_policy, account: account, policy_type: "registry_allowlist", name: "Registry") }
    let!(:vuln_policy) { create(:supply_chain_image_policy, account: account, policy_type: "vulnerability_threshold", name: "Vuln") }
    let!(:sig_policy) { create(:supply_chain_image_policy, account: account, policy_type: "signature_required", name: "Sig") }
    let!(:block_policy) { create(:supply_chain_image_policy, account: account, enforcement_level: "block", name: "Block") }
    let!(:warn_policy) { create(:supply_chain_image_policy, account: account, enforcement_level: "warn", name: "Warn") }
    let!(:log_policy) { create(:supply_chain_image_policy, account: account, enforcement_level: "log", name: "Log") }
    let!(:high_priority_policy) { create(:supply_chain_image_policy, account: account, priority: 10, name: "High Priority") }
    let!(:low_priority_policy) { create(:supply_chain_image_policy, account: account, priority: 1, name: "Low Priority") }

    describe "active scope" do
      it "returns only active policies" do
        expect(described_class.active).to include(active_policy)
        expect(described_class.active).not_to include(inactive_policy)
      end
    end

    describe "inactive scope" do
      it "returns only inactive policies" do
        expect(described_class.inactive).to include(inactive_policy)
        expect(described_class.inactive).not_to include(active_policy)
      end
    end

    describe "by_type scope" do
      it "filters policies by type" do
        expect(described_class.by_type("registry_allowlist")).to include(registry_policy)
        expect(described_class.by_type("vulnerability_threshold")).to include(vuln_policy)
        expect(described_class.by_type("signature_required")).to include(sig_policy)
      end

      it "excludes other policy types" do
        result = described_class.by_type("registry_allowlist")
        expect(result).not_to include(vuln_policy, sig_policy)
      end
    end

    describe "blocking scope" do
      it "returns policies with block enforcement level" do
        expect(described_class.blocking).to include(block_policy)
        expect(described_class.blocking).not_to include(warn_policy, log_policy)
      end
    end

    describe "warning scope" do
      it "returns policies with warn enforcement level" do
        expect(described_class.warning).to include(warn_policy)
        expect(described_class.warning).not_to include(block_policy, log_policy)
      end
    end

    describe "ordered scope" do
      it "orders by priority descending, then created_at ascending" do
        result = described_class.ordered
        priorities = result.pluck(:priority)
        # Check that priorities are in descending order
        expect(priorities).to eq(priorities.sort.reverse)
      end
    end

    describe "signature_policies scope" do
      it "returns only signature_required policies" do
        expect(described_class.signature_policies).to include(sig_policy)
        expect(described_class.signature_policies).not_to include(registry_policy, vuln_policy)
      end
    end

    describe "vuln_policies scope" do
      it "returns only vulnerability_threshold policies" do
        expect(described_class.vuln_policies).to include(vuln_policy)
        expect(described_class.vuln_policies).not_to include(registry_policy, sig_policy)
      end
    end
  end

  describe "callbacks" do
    describe "sanitize_jsonb_fields" do
      it "initializes match_rules to empty hash if nil" do
        policy = create(:supply_chain_image_policy, account: account, match_rules: nil)
        expect(policy.match_rules).to eq({})
      end

      it "initializes rules to empty hash if nil" do
        policy = create(:supply_chain_image_policy, account: account, rules: nil)
        expect(policy.rules).to eq({})
      end

      it "initializes metadata to empty hash if nil" do
        policy = create(:supply_chain_image_policy, account: account, metadata: nil)
        expect(policy.metadata).to eq({})
      end

      it "preserves existing jsonb values" do
        match_rules = { "registries" => [ "gcr.io" ] }
        rules = { "allowed_registries" => [ "docker.io" ] }
        metadata = { "key" => "value" }
        policy = create(:supply_chain_image_policy,
                       account: account,
                       match_rules: match_rules,
                       rules: rules,
                       metadata: metadata)
        expect(policy.match_rules).to eq(match_rules)
        expect(policy.rules).to eq(rules)
        expect(policy.metadata).to eq(metadata)
      end
    end
  end

  describe "instance methods" do
    describe "#active?" do
      it "returns true when is_active is true" do
        policy = build(:supply_chain_image_policy, is_active: true)
        expect(policy.active?).to be true
      end

      it "returns false when is_active is false" do
        policy = build(:supply_chain_image_policy, is_active: false)
        expect(policy.active?).to be false
      end
    end

    describe "#blocking?" do
      it "returns true when enforcement_level is block" do
        policy = build(:supply_chain_image_policy, enforcement_level: "block")
        expect(policy.blocking?).to be true
      end

      it "returns false for other enforcement levels" do
        policy = build(:supply_chain_image_policy, enforcement_level: "warn")
        expect(policy.blocking?).to be false
      end
    end

    describe "#warning?" do
      it "returns true when enforcement_level is warn" do
        policy = build(:supply_chain_image_policy, enforcement_level: "warn")
        expect(policy.warning?).to be true
      end

      it "returns false for other enforcement levels" do
        policy = build(:supply_chain_image_policy, enforcement_level: "block")
        expect(policy.warning?).to be false
      end
    end

    describe "#logging?" do
      it "returns true when enforcement_level is log" do
        policy = build(:supply_chain_image_policy, enforcement_level: "log")
        expect(policy.logging?).to be true
      end

      it "returns false for other enforcement levels" do
        policy = build(:supply_chain_image_policy, enforcement_level: "warn")
        expect(policy.logging?).to be false
      end
    end

    describe "#registry_allowlist?" do
      it "returns true when policy_type is registry_allowlist" do
        policy = build(:supply_chain_image_policy, policy_type: "registry_allowlist")
        expect(policy.registry_allowlist?).to be true
      end

      it "returns false for other policy types" do
        policy = build(:supply_chain_image_policy, policy_type: "signature_required")
        expect(policy.registry_allowlist?).to be false
      end
    end

    describe "#signature_required?" do
      it "returns true when policy_type is signature_required" do
        policy = build(:supply_chain_image_policy, policy_type: "signature_required")
        expect(policy.signature_required?).to be true
      end

      it "returns false for other policy types" do
        policy = build(:supply_chain_image_policy, policy_type: "registry_allowlist")
        expect(policy.signature_required?).to be false
      end
    end

    describe "#vulnerability_threshold?" do
      it "returns true when policy_type is vulnerability_threshold" do
        policy = build(:supply_chain_image_policy, policy_type: "vulnerability_threshold")
        expect(policy.vulnerability_threshold?).to be true
      end

      it "returns false for other policy types" do
        policy = build(:supply_chain_image_policy, policy_type: "custom")
        expect(policy.vulnerability_threshold?).to be false
      end
    end

    describe "#custom?" do
      it "returns true when policy_type is custom" do
        policy = build(:supply_chain_image_policy, policy_type: "custom")
        expect(policy.custom?).to be true
      end

      it "returns false for other policy types" do
        policy = build(:supply_chain_image_policy, policy_type: "registry_allowlist")
        expect(policy.custom?).to be false
      end
    end

    describe "#activate!" do
      it "sets is_active to true" do
        policy = create(:supply_chain_image_policy, account: account, is_active: false)
        policy.activate!
        expect(policy.reload.is_active).to be true
      end
    end

    describe "#deactivate!" do
      it "sets is_active to false" do
        policy = create(:supply_chain_image_policy, account: account, is_active: true)
        policy.deactivate!
        expect(policy.reload.is_active).to be false
      end
    end

    describe "#summary" do
      let(:policy) do
        create(:supply_chain_image_policy,
               account: account,
               name: "Test Policy",
               description: "Test description",
               policy_type: "vulnerability_threshold",
               enforcement_level: "block",
               is_active: true,
               priority: 5,
               require_signature: true,
               require_sbom: true,
               max_critical_vulns: 1,
               max_high_vulns: 5)
      end

      it "returns a hash with policy details" do
        summary = policy.summary
        expect(summary).to be_a(Hash)
        expect(summary[:id]).to eq(policy.id)
        expect(summary[:name]).to eq("Test Policy")
        expect(summary[:description]).to eq("Test description")
        expect(summary[:policy_type]).to eq("vulnerability_threshold")
        expect(summary[:enforcement_level]).to eq("block")
        expect(summary[:is_active]).to be true
        expect(summary[:priority]).to eq(5)
        expect(summary[:require_signature]).to be true
        expect(summary[:require_sbom]).to be true
        expect(summary[:max_critical_vulns]).to eq(1)
        expect(summary[:max_high_vulns]).to eq(5)
        expect(summary[:created_at]).to eq(policy.created_at)
      end
    end

    describe "#matches_image?" do
      let(:policy) { create(:supply_chain_image_policy, account: account) }
      let(:image) do
        build(:supply_chain_container_image,
              registry: "gcr.io",
              repository: "project/app",
              tag: "v1.0.0",
              labels: { "env" => "prod", "version" => "1.0" })
      end

      context "when match_rules is blank" do
        it "returns true for any image" do
          policy.update!(match_rules: {})
          expect(policy.matches_image?(image)).to be true
        end

        it "returns true when match_rules is nil" do
          policy.update!(match_rules: nil)
          expect(policy.matches_image?(image)).to be true
        end
      end

      context "when registries match rules exist" do
        before { policy.update!(match_rules: { "registries" => [ "gcr.io", "docker.io" ] }) }

        it "returns true when registry matches" do
          expect(policy.matches_image?(image)).to be true
        end

        it "returns false when registry does not match" do
          image.registry = "quay.io"
          expect(policy.matches_image?(image)).to be false
        end

        it "supports regex patterns" do
          policy.update!(match_rules: { "registries" => [ "gcr\\.io", "docker\\.io" ] })
          expect(policy.matches_image?(image)).to be true
        end
      end

      context "when repositories match rules exist" do
        before { policy.update!(match_rules: { "repositories" => [ "project/app", "project/other" ] }) }

        it "returns true when repository matches" do
          expect(policy.matches_image?(image)).to be true
        end

        it "returns false when repository does not match" do
          image.repository = "other/app"
          expect(policy.matches_image?(image)).to be false
        end

        it "supports regex patterns" do
          policy.update!(match_rules: { "repositories" => [ "project/.*" ] })
          expect(policy.matches_image?(image)).to be true
        end
      end

      context "when tags match rules exist" do
        before { policy.update!(match_rules: { "tags" => [ "v1.0.0", "v1.0.1" ] }) }

        it "returns true when tag matches" do
          expect(policy.matches_image?(image)).to be true
        end

        it "returns false when tag does not match" do
          image.tag = "v2.0.0"
          expect(policy.matches_image?(image)).to be false
        end

        it "returns false when image has no tag" do
          image.tag = nil
          expect(policy.matches_image?(image)).to be false
        end

        it "supports regex patterns" do
          policy.update!(match_rules: { "tags" => [ "v1\\..*" ] })
          expect(policy.matches_image?(image)).to be true
        end
      end

      context "when labels match rules exist" do
        before { policy.update!(match_rules: { "labels" => { "env" => "prod", "version" => "1.0" } }) }

        it "returns true when all labels match" do
          expect(policy.matches_image?(image)).to be true
        end

        it "returns false when a label does not match" do
          image.labels["env"] = "staging"
          expect(policy.matches_image?(image)).to be false
        end

        it "returns false when required label is missing" do
          image.labels.delete("env")
          expect(policy.matches_image?(image)).to be false
        end
      end

      context "when multiple match rules exist" do
        before do
          policy.update!(match_rules: {
            "registries" => [ "gcr.io" ],
            "repositories" => [ "project/app" ],
            "tags" => [ "v1.0.0" ]
          })
        end

        it "returns true when all rules match" do
          expect(policy.matches_image?(image)).to be true
        end

        it "returns false when one rule does not match" do
          image.tag = "v2.0.0"
          expect(policy.matches_image?(image)).to be false
        end
      end
    end

    describe "#evaluate" do
      let(:policy) do
        create(:supply_chain_image_policy,
               account: account,
               name: "Test Policy",
               policy_type: "registry_allowlist",
               enforcement_level: "warn",
               require_signature: false,
               rules: { "allowed_registries" => [ "gcr.io", "docker.io" ] })
      end
      let(:image) do
        build(:supply_chain_container_image,
              registry: "gcr.io",
              repository: "project/app",
              tag: "v1.0.0")
      end

      it "returns a result hash with basic structure" do
        result = policy.evaluate(image)
        expect(result).to include(
          policy_id: policy.id,
          policy_name: "Test Policy",
          policy_type: "registry_allowlist",
          enforcement_level: "warn",
          passed: true,
          violations: []
        )
      end

      context "when policy does not match image" do
        before { policy.update!(match_rules: { "registries" => [ "docker.io" ] }) }

        it "returns skipped result" do
          result = policy.evaluate(image)
          expect(result[:skipped]).to be true
          expect(result[:reason]).to eq("Policy does not match image")
        end
      end

      context "with registry_allowlist policy" do
        before { policy.update!(policy_type: "registry_allowlist") }

        context "with denied registries" do
          before { policy.update!(rules: { "denied_registries" => [ "gcr.io" ] }) }

          it "marks as failed when registry is denied" do
            result = policy.evaluate(image)
            expect(result[:passed]).to be false
            expect(result[:violations]).to include(
              hash_including(
                type: "denied_registry",
                message: include("is explicitly denied")
              )
            )
          end

          it "marks as passed when registry is not denied" do
            image.registry = "docker.io"
            result = policy.evaluate(image)
            expect(result[:passed]).to be true
          end
        end

        context "with allowed registries" do
          before { policy.update!(rules: { "allowed_registries" => [ "docker.io" ] }) }

          it "marks as failed when registry not in allowlist" do
            result = policy.evaluate(image)
            expect(result[:passed]).to be false
            expect(result[:violations]).to include(
              hash_including(
                type: "registry_not_allowed",
                message: include("is not in the allowlist")
              )
            )
          end

          it "marks as passed when registry is in allowlist" do
            image.registry = "docker.io"
            result = policy.evaluate(image)
            expect(result[:passed]).to be true
          end
        end
      end

      context "with signature_required policy" do
        before do
          policy.update!(
            policy_type: "signature_required",
            require_signature: true,
            require_sbom: false
          )
        end

        it "marks as failed when image is not signed" do
          allow(image).to receive(:signed?).and_return(false)
          result = policy.evaluate(image)
          expect(result[:passed]).to be false
          expect(result[:violations]).to include(
            hash_including(
              type: "signature_missing",
              message: "Image is not signed"
            )
          )
        end

        it "marks as passed when image is signed" do
          allow(image).to receive(:signed?).and_return(true)
          result = policy.evaluate(image)
          expect(result[:passed]).to be true
        end

        context "when require_sbom is true" do
          before { policy.update!(require_sbom: true) }

          it "marks as failed when SBOM is missing" do
            allow(image).to receive(:signed?).and_return(true)
            allow(image).to receive(:sbom).and_return(nil)
            result = policy.evaluate(image)
            expect(result[:passed]).to be false
            expect(result[:violations]).to include(
              hash_including(
                type: "sbom_missing",
                message: "Image does not have an associated SBOM"
              )
            )
          end

          it "marks as passed when signature and SBOM present" do
            allow(image).to receive(:signed?).and_return(true)
            allow(image).to receive(:sbom).and_return(build(:supply_chain_sbom))
            result = policy.evaluate(image)
            expect(result[:passed]).to be true
          end
        end
      end

      context "with vulnerability_threshold policy" do
        before do
          policy.update!(
            policy_type: "vulnerability_threshold",
            max_critical_vulns: 2,
            max_high_vulns: 5
          )
        end

        it "marks as failed when critical vulns exceed threshold" do
          allow(image).to receive(:critical_vuln_count).and_return(3)
          allow(image).to receive(:high_vuln_count).and_return(0)
          result = policy.evaluate(image)
          expect(result[:passed]).to be false
          expect(result[:violations]).to include(
            hash_including(
              type: "critical_vuln_exceeded",
              message: include("3 critical vulnerabilities")
            )
          )
        end

        it "marks as failed when high vulns exceed threshold" do
          allow(image).to receive(:critical_vuln_count).and_return(0)
          allow(image).to receive(:high_vuln_count).and_return(6)
          result = policy.evaluate(image)
          expect(result[:passed]).to be false
          expect(result[:violations]).to include(
            hash_including(
              type: "high_vuln_exceeded",
              message: include("6 high vulnerabilities")
            )
          )
        end

        it "marks as passed when vulns are within thresholds" do
          allow(image).to receive(:critical_vuln_count).and_return(1)
          allow(image).to receive(:high_vuln_count).and_return(4)
          result = policy.evaluate(image)
          expect(result[:passed]).to be true
        end

        it "ignores nil max thresholds" do
          policy.update!(max_critical_vulns: nil, max_high_vulns: nil)
          allow(image).to receive(:critical_vuln_count).and_return(100)
          allow(image).to receive(:high_vuln_count).and_return(100)
          result = policy.evaluate(image)
          expect(result[:passed]).to be true
        end
      end

      context "with custom policy" do
        before { policy.update!(policy_type: "custom") }

        context "label_required check" do
          before do
            policy.update!(rules: {
              "checks" => [
                { "type" => "label_required", "key" => "app" }
              ]
            })
            image.labels = { "app" => "myapp", "version" => "1.0" }
          end

          it "marks as failed when required label is missing" do
            image.labels = {}
            result = policy.evaluate(image)
            expect(result[:passed]).to be false
            expect(result[:violations]).to include(
              hash_including(
                type: "label_missing",
                message: "Required label 'app' is missing"
              )
            )
          end

          it "marks as passed when required label is present" do
            result = policy.evaluate(image)
            expect(result[:passed]).to be true
          end
        end

        context "label_value check" do
          before do
            policy.update!(rules: {
              "checks" => [
                { "type" => "label_value", "key" => "env", "value" => "prod" }
              ]
            })
            image.labels = { "env" => "prod" }
          end

          it "marks as failed when label value does not match" do
            image.labels["env"] = "staging"
            result = policy.evaluate(image)
            expect(result[:passed]).to be false
            expect(result[:violations]).to include(
              hash_including(
                type: "label_value_mismatch",
                message: "Label 'env' must have value 'prod'"
              )
            )
          end

          it "marks as passed when label value matches" do
            result = policy.evaluate(image)
            expect(result[:passed]).to be true
          end
        end

        context "max_age_days check" do
          before do
            policy.update!(rules: {
              "checks" => [
                { "type" => "max_age_days", "days" => 30 }
              ]
            })
          end

          it "marks as failed when image is too old" do
            allow(image).to receive(:pushed_at).and_return(45.days.ago)
            result = policy.evaluate(image)
            expect(result[:passed]).to be false
            expect(result[:violations]).to include(
              hash_including(
                type: "image_too_old",
                message: "Image is older than 30 days"
              )
            )
          end

          it "marks as passed when image is recent" do
            allow(image).to receive(:pushed_at).and_return(15.days.ago)
            result = policy.evaluate(image)
            expect(result[:passed]).to be true
          end

          it "marks as passed when pushed_at is nil" do
            allow(image).to receive(:pushed_at).and_return(nil)
            result = policy.evaluate(image)
            expect(result[:passed]).to be true
          end
        end

        context "multiple checks" do
          before do
            policy.update!(rules: {
              "checks" => [
                { "type" => "label_required", "key" => "app" },
                { "type" => "label_value", "key" => "env", "value" => "prod" }
              ]
            })
            image.labels = { "app" => "myapp", "env" => "prod" }
          end

          it "marks as failed when any check fails" do
            image.labels["env"] = "staging"
            result = policy.evaluate(image)
            expect(result[:passed]).to be false
            expect(result[:violations].length).to eq(1)
          end

          it "marks as passed when all checks pass" do
            result = policy.evaluate(image)
            expect(result[:passed]).to be true
          end
        end
      end
    end
  end

  describe "Auditable concern" do
    it "includes Auditable module" do
      expect(described_class.ancestors).to include(Auditable)
    end

    it "has auditable_attributes method (private)" do
      policy = build(:supply_chain_image_policy, account: account)
      expect(policy.send(:auditable_attributes)).to be_a(Hash)
    end
  end
end
