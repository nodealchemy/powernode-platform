# frozen_string_literal: true

require "rails_helper"

RSpec.describe SupplyChain::Attribution, type: :model do
  let(:account) { create(:account) }
  let(:sbom) { create(:supply_chain_sbom, account: account) }
  let(:sbom_component) { create(:supply_chain_sbom_component, sbom: sbom, account: account) }
  let(:license) { create(:supply_chain_license, :permissive) }

  describe "associations" do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:sbom_component).class_name("SupplyChain::SbomComponent") }
    it { is_expected.to belong_to(:license).class_name("SupplyChain::License").optional }
  end

  describe "validations" do
    subject { build(:supply_chain_attribution, sbom_component: sbom_component, account: account) }

    # Note: package_name presence is validated, but before_validation callback
    # populates it from sbom_component, so shoulda-matchers can't test it directly
    it "requires package_name" do
      # Test by setting nil AFTER callback runs via persisted record update
      attr = create(:supply_chain_attribution, sbom_component: sbom_component, account: account)
      attr.package_name = nil
      expect(attr).not_to be_valid
      expect(attr.errors[:package_name]).to include("can't be blank")
    end

    it "validates uniqueness of sbom_component_id" do
      create(:supply_chain_attribution, sbom_component: sbom_component, account: account)
      duplicate = build(:supply_chain_attribution, sbom_component: sbom_component, account: account)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:sbom_component_id]).to include("has already been taken")
    end
  end

  describe "scopes" do
    let!(:mit_license) { create(:supply_chain_license, spdx_id: "MIT", category: "permissive") }
    let!(:gpl_license) { create(:supply_chain_license, :copyleft) }

    let!(:attr_requiring_attribution) do
      create(:supply_chain_attribution,
             account: account,
             sbom_component: create(:supply_chain_sbom_component, sbom: sbom, account: account),
             license: mit_license,
             requires_attribution: true,
             package_name: "package-a")
    end

    let!(:attr_requiring_license_copy) do
      create(:supply_chain_attribution,
             account: account,
             sbom_component: create(:supply_chain_sbom_component, sbom: sbom, account: account),
             license: gpl_license,
             requires_license_copy: true,
             package_name: "package-b")
    end

    let!(:attr_requiring_source_disclosure) do
      create(:supply_chain_attribution,
             account: account,
             sbom_component: create(:supply_chain_sbom_component, sbom: sbom, account: account),
             license: gpl_license,
             requires_source_disclosure: true,
             package_name: "package-c")
    end

    let!(:attr_with_license_text) do
      create(:supply_chain_attribution,
             account: account,
             sbom_component: create(:supply_chain_sbom_component, sbom: sbom, account: account),
             license: mit_license,
             license_text: "MIT License text...",
             package_name: "package-d")
    end

    let!(:attr_with_notice_text) do
      create(:supply_chain_attribution,
             account: account,
             sbom_component: create(:supply_chain_sbom_component, sbom: sbom, account: account),
             license: mit_license,
             notice_text: "Notice text...",
             package_name: "package-e")
    end

    let!(:attr_no_special_text) do
      create(:supply_chain_attribution,
             account: account,
             sbom_component: create(:supply_chain_sbom_component, sbom: sbom, account: account),
             license: mit_license,
             requires_attribution: false,
             package_name: "package-f")
    end

    describe ".requiring_attribution" do
      it "returns attributions that require attribution" do
        expect(described_class.requiring_attribution).to include(attr_requiring_attribution)
        expect(described_class.requiring_attribution).not_to include(attr_no_special_text)
      end
    end

    describe ".requiring_license_copy" do
      it "returns attributions that require license copy" do
        expect(described_class.requiring_license_copy).to include(attr_requiring_license_copy)
        expect(described_class.requiring_license_copy).not_to include(attr_requiring_attribution)
      end
    end

    describe ".requiring_source_disclosure" do
      it "returns attributions that require source disclosure" do
        expect(described_class.requiring_source_disclosure).to include(attr_requiring_source_disclosure)
        expect(described_class.requiring_source_disclosure).not_to include(attr_requiring_attribution)
      end
    end

    describe ".with_license_text" do
      it "returns attributions with license text" do
        expect(described_class.with_license_text).to include(attr_with_license_text)
        expect(described_class.with_license_text).not_to include(attr_no_special_text)
      end
    end

    describe ".with_notice_text" do
      it "returns attributions with notice text" do
        expect(described_class.with_notice_text).to include(attr_with_notice_text)
        expect(described_class.with_notice_text).not_to include(attr_no_special_text)
      end
    end

    describe ".alphabetical" do
      it "orders attributions by package name ascending" do
        ordered = described_class.alphabetical
        expect(ordered.first.package_name).to eq("package-a")
        expect(ordered.last.package_name).to eq("package-f")
      end
    end

    describe ".by_license" do
      it "filters attributions by license_id" do
        results = described_class.by_license(mit_license.id)
        expect(results).to include(attr_requiring_attribution, attr_with_license_text, attr_with_notice_text)
        expect(results).not_to include(attr_requiring_license_copy, attr_requiring_source_disclosure)
      end
    end
  end

  describe "callbacks" do
    describe "populate_from_component" do
      context "on create" do
        let(:component) do
          create(:supply_chain_sbom_component,
                 sbom: sbom,
                 account: account,
                 name: "test-package",
                 namespace: "@test",
                 version: "1.2.3",
                 license_spdx_id: "MIT")
        end

        let(:mit_license) { create(:supply_chain_license, spdx_id: "MIT", category: "permissive") }

        it "populates package_name from component" do
          attribution = described_class.create!(
            account: account,
            sbom_component: component
          )

          expect(attribution.package_name).to eq(component.full_name)
        end

        it "populates package_version from component" do
          attribution = described_class.create!(
            account: account,
            sbom_component: component
          )

          expect(attribution.package_version).to eq("1.2.3")
        end

        it "finds and assigns license from component's license_spdx_id" do
          mit_license # ensure license exists
          attribution = described_class.create!(
            account: account,
            sbom_component: component
          )

          expect(attribution.license).to eq(mit_license)
        end

        it "does not override manually set values" do
          attribution = described_class.create!(
            account: account,
            sbom_component: component,
            package_name: "custom-name",
            package_version: "9.9.9"
          )

          expect(attribution.package_name).to eq("custom-name")
          expect(attribution.package_version).to eq("9.9.9")
        end
      end
    end

    describe "sanitize_jsonb_fields" do
      it "initializes metadata as empty hash when nil" do
        attribution = create(:supply_chain_attribution,
                            account: account,
                            sbom_component: sbom_component,
                            metadata: nil)
        expect(attribution.metadata).to eq({})
      end

      it "preserves existing metadata" do
        attribution = create(:supply_chain_attribution,
                            account: account,
                            sbom_component: sbom_component,
                            metadata: { "key" => "value" })
        attribution.reload
        expect(attribution.metadata).to eq({ "key" => "value" })
      end
    end

    describe "set_requirements_from_license" do
      context "when license is present" do
        let(:copyleft_license) do
          create(:supply_chain_license,
                 :copyleft,
                 spdx_id: "GPL-3.0-only",
                 category: "copyleft",
                 is_copyleft: true,
                 is_strong_copyleft: true)
        end

        it "sets requires_attribution from license" do
          attribution = create(:supply_chain_attribution,
                              account: account,
                              sbom_component: sbom_component,
                              license: copyleft_license,
                              requires_attribution: nil)
          expect(attribution.requires_attribution).to be true
        end

        it "sets requires_license_copy from license" do
          attribution = create(:supply_chain_attribution,
                              account: account,
                              sbom_component: sbom_component,
                              license: copyleft_license,
                              requires_license_copy: nil)
          expect(attribution.requires_license_copy).to be true
        end

        it "sets requires_source_disclosure from license" do
          attribution = create(:supply_chain_attribution,
                              account: account,
                              sbom_component: sbom_component,
                              license: copyleft_license,
                              requires_source_disclosure: nil)
          expect(attribution.requires_source_disclosure).to be true
        end

        it "does not override explicitly set values" do
          attribution = create(:supply_chain_attribution,
                              account: account,
                              sbom_component: sbom_component,
                              license: copyleft_license,
                              requires_attribution: false)
          expect(attribution.requires_attribution).to be false
        end
      end

      context "when license is not present" do
        it "does not override explicit requirement flags" do
          # DB has NOT NULL constraint, so test that callback doesn't override explicit false
          attribution = create(:supply_chain_attribution,
                              account: account,
                              sbom_component: sbom_component,
                              license: nil,
                              requires_attribution: false)
          expect(attribution.requires_attribution).to be false
        end
      end
    end
  end

  describe "requirement predicates" do
    describe "#requires_attribution?" do
      it "returns true when requires_attribution is true" do
        attribution = build(:supply_chain_attribution, requires_attribution: true)
        expect(attribution.requires_attribution?).to be true
      end

      it "returns false when requires_attribution is false" do
        attribution = build(:supply_chain_attribution, requires_attribution: false)
        expect(attribution.requires_attribution?).to be false
      end
    end

    describe "#requires_license_copy?" do
      it "returns true when requires_license_copy is true" do
        attribution = build(:supply_chain_attribution, requires_license_copy: true)
        expect(attribution.requires_license_copy?).to be true
      end

      it "returns false when requires_license_copy is false" do
        attribution = build(:supply_chain_attribution, requires_license_copy: false)
        expect(attribution.requires_license_copy?).to be false
      end
    end

    describe "#requires_source_disclosure?" do
      it "returns true when requires_source_disclosure is true" do
        attribution = build(:supply_chain_attribution, requires_source_disclosure: true)
        expect(attribution.requires_source_disclosure?).to be true
      end

      it "returns false when requires_source_disclosure is false" do
        attribution = build(:supply_chain_attribution, requires_source_disclosure: false)
        expect(attribution.requires_source_disclosure?).to be false
      end
    end
  end

  describe "text presence predicates" do
    describe "#has_license_text?" do
      it "returns true when license_text is present" do
        attribution = build(:supply_chain_attribution, license_text: "MIT License text")
        expect(attribution.has_license_text?).to be true
      end

      it "returns false when license_text is nil" do
        attribution = build(:supply_chain_attribution, license_text: nil)
        expect(attribution.has_license_text?).to be false
      end

      it "returns false when license_text is empty string" do
        attribution = build(:supply_chain_attribution, license_text: "")
        expect(attribution.has_license_text?).to be false
      end
    end

    describe "#has_notice_text?" do
      it "returns true when notice_text is present" do
        attribution = build(:supply_chain_attribution, notice_text: "Notice text")
        expect(attribution.has_notice_text?).to be true
      end

      it "returns false when notice_text is nil" do
        attribution = build(:supply_chain_attribution, notice_text: nil)
        expect(attribution.has_notice_text?).to be false
      end

      it "returns false when notice_text is empty string" do
        attribution = build(:supply_chain_attribution, notice_text: "")
        expect(attribution.has_notice_text?).to be false
      end
    end
  end

  describe "license delegation methods" do
    describe "#license_name" do
      it "returns license name when license is present" do
        mit = create(:supply_chain_license, spdx_id: "MIT", name: "MIT License")
        attribution = build(:supply_chain_attribution, license: mit)
        expect(attribution.license_name).to eq("MIT License")
      end

      it "returns nil when license is not present" do
        attribution = build(:supply_chain_attribution, license: nil)
        expect(attribution.license_name).to be_nil
      end
    end

    describe "#license_spdx_id" do
      it "returns license spdx_id when license is present" do
        mit = create(:supply_chain_license, spdx_id: "MIT")
        attribution = build(:supply_chain_attribution, license: mit)
        expect(attribution.license_spdx_id).to eq("MIT")
      end

      it "returns nil when license is not present" do
        attribution = build(:supply_chain_attribution, license: nil)
        expect(attribution.license_spdx_id).to be_nil
      end
    end
  end

  describe "#full_attribution_text" do
    let(:mit) { create(:supply_chain_license, spdx_id: "MIT", name: "MIT License") }

    it "includes package name with separator" do
      attribution = build(:supply_chain_attribution, package_name: "test-package")
      text = attribution.full_attribution_text
      expect(text).to include("=" * 60)
      expect(text).to include("test-package")
    end

    it "includes version when present" do
      attribution = build(:supply_chain_attribution, package_name: "test-package", package_version: "1.2.3")
      text = attribution.full_attribution_text
      expect(text).to include("Version: 1.2.3")
    end

    it "excludes version when not present" do
      attribution = build(:supply_chain_attribution, package_name: "test-package", package_version: nil)
      text = attribution.full_attribution_text
      expect(text).not_to include("Version:")
    end

    it "includes copyright holder when present" do
      attribution = build(:supply_chain_attribution,
                         package_name: "test-package",
                         copyright_holder: "Acme Corp")
      text = attribution.full_attribution_text
      expect(text).to include("Copyright")
      expect(text).to include("Acme Corp")
    end

    it "includes copyright year when present" do
      attribution = build(:supply_chain_attribution,
                         package_name: "test-package",
                         copyright_holder: "Acme Corp",
                         copyright_year: "2023")
      text = attribution.full_attribution_text
      expect(text).to include("Copyright (c) 2023 Acme Corp")
    end

    it "includes license information when license is present" do
      attribution = build(:supply_chain_attribution,
                         package_name: "test-package",
                         license: mit)
      text = attribution.full_attribution_text
      expect(text).to include("License: MIT License (MIT)")
    end

    it "includes notice text when present" do
      attribution = build(:supply_chain_attribution,
                         package_name: "test-package",
                         notice_text: "This is a notice")
      text = attribution.full_attribution_text
      expect(text).to include("NOTICE:")
      expect(text).to include("This is a notice")
    end

    it "includes license text when requires_license_copy is true and license_text is present" do
      attribution = build(:supply_chain_attribution,
                         package_name: "test-package",
                         requires_license_copy: true,
                         license_text: "Full MIT license text")
      text = attribution.full_attribution_text
      expect(text).to include("LICENSE TEXT:")
      expect(text).to include("-" * 40)
      expect(text).to include("Full MIT license text")
    end

    it "excludes license text when requires_license_copy is false" do
      attribution = build(:supply_chain_attribution,
                         package_name: "test-package",
                         requires_license_copy: false,
                         license_text: "Full MIT license text")
      text = attribution.full_attribution_text
      expect(text).not_to include("LICENSE TEXT:")
      expect(text).not_to include("Full MIT license text")
    end

    it "includes attribution URL when present" do
      attribution = build(:supply_chain_attribution,
                         package_name: "test-package",
                         attribution_url: "https://example.com/license")
      text = attribution.full_attribution_text
      expect(text).to include("URL: https://example.com/license")
    end

    it "generates complete attribution text with all fields" do
      attribution = build(:supply_chain_attribution,
                         package_name: "lodash",
                         package_version: "4.17.21",
                         copyright_holder: "JS Foundation",
                         copyright_year: "2012",
                         license: mit,
                         notice_text: "This package includes utilities",
                         requires_license_copy: true,
                         license_text: "Permission is hereby granted...",
                         attribution_url: "https://lodash.com")
      text = attribution.full_attribution_text

      expect(text).to include("lodash")
      expect(text).to include("Version: 4.17.21")
      expect(text).to include("Copyright (c) 2012 JS Foundation")
      expect(text).to include("License: MIT License (MIT)")
      expect(text).to include("NOTICE:")
      expect(text).to include("This package includes utilities")
      expect(text).to include("LICENSE TEXT:")
      expect(text).to include("Permission is hereby granted...")
      expect(text).to include("URL: https://lodash.com")
    end
  end

  describe "#to_notice_entry" do
    let(:mit) { create(:supply_chain_license, spdx_id: "MIT", name: "MIT License") }

    it "includes package name" do
      attribution = build(:supply_chain_attribution, package_name: "test-package")
      entry = attribution.to_notice_entry
      expect(entry).to include("test-package")
    end

    it "includes version when present" do
      attribution = build(:supply_chain_attribution,
                         package_name: "test-package",
                         package_version: "1.2.3")
      entry = attribution.to_notice_entry
      expect(entry).to include("test-package 1.2.3")
    end

    it "includes license name when present" do
      attribution = build(:supply_chain_attribution,
                         package_name: "test-package",
                         package_version: nil,
                         license: mit)
      entry = attribution.to_notice_entry
      expect(entry).to include("test-package - MIT License")
    end

    it "includes copyright holder on new line" do
      attribution = build(:supply_chain_attribution,
                         package_name: "test-package",
                         copyright_holder: "Acme Corp")
      entry = attribution.to_notice_entry
      expect(entry).to include("\n  Copyright Acme Corp")
    end

    it "includes copyright year when present" do
      attribution = build(:supply_chain_attribution,
                         package_name: "test-package",
                         copyright_holder: "Acme Corp",
                         copyright_year: "2023")
      entry = attribution.to_notice_entry
      expect(entry).to include("\n  Copyright (c) 2023 Acme Corp")
    end

    it "generates complete notice entry with all fields" do
      attribution = build(:supply_chain_attribution,
                         package_name: "lodash",
                         package_version: "4.17.21",
                         license: mit,
                         copyright_holder: "JS Foundation",
                         copyright_year: "2012")
      entry = attribution.to_notice_entry

      expect(entry).to eq("lodash 4.17.21 - MIT License\n  Copyright (c) 2012 JS Foundation")
    end
  end

  describe "#summary" do
    let(:mit) { create(:supply_chain_license, spdx_id: "MIT", name: "MIT License") }

    it "returns a hash with all expected keys" do
      attribution = create(:supply_chain_attribution,
                          account: account,
                          sbom_component: sbom_component,
                          license: mit,
                          package_name: "test-package",
                          package_version: "1.2.3",
                          copyright_holder: "Acme Corp",
                          copyright_year: "2023",
                          requires_attribution: true,
                          requires_license_copy: false,
                          requires_source_disclosure: false,
                          license_text: "MIT text",
                          notice_text: "Notice",
                          attribution_url: "https://example.com")

      summary = attribution.summary

      expect(summary).to include(
        :id,
        :sbom_component_id,
        :package_name,
        :package_version,
        :license_id,
        :license_name,
        :license_spdx_id,
        :copyright_holder,
        :copyright_year,
        :requires_attribution,
        :requires_license_copy,
        :requires_source_disclosure,
        :has_license_text,
        :has_notice_text,
        :attribution_url
      )

      expect(summary[:package_name]).to eq("test-package")
      expect(summary[:package_version]).to eq("1.2.3")
      expect(summary[:license_name]).to eq("MIT License")
      expect(summary[:license_spdx_id]).to eq("MIT")
      expect(summary[:has_license_text]).to be true
      expect(summary[:has_notice_text]).to be true
    end
  end

  describe ".generate_notice_file" do
    let!(:mit) { create(:supply_chain_license, spdx_id: "MIT", name: "MIT License") }
    let!(:apache) { create(:supply_chain_license, spdx_id: "Apache-2.0", name: "Apache License 2.0") }

    let!(:attribution1) do
      create(:supply_chain_attribution,
             account: account,
             sbom_component: create(:supply_chain_sbom_component, sbom: sbom, account: account),
             license: mit,
             package_name: "lodash",
             package_version: "4.17.21",
             copyright_holder: "JS Foundation")
    end

    let!(:attribution2) do
      create(:supply_chain_attribution,
             account: account,
             sbom_component: create(:supply_chain_sbom_component, sbom: sbom, account: account),
             license: mit,
             package_name: "axios",
             package_version: "1.0.0",
             copyright_holder: "Matt Zabriskie")
    end

    let!(:attribution3) do
      create(:supply_chain_attribution,
             account: account,
             sbom_component: create(:supply_chain_sbom_component, sbom: sbom, account: account),
             license: apache,
             package_name: "spring-boot",
             package_version: "2.7.0",
             copyright_holder: "Pivotal Software",
             requires_license_copy: true,
             license_text: "Apache License 2.0 full text...")
    end

    it "generates notice file with header" do
      notice = described_class.generate_notice_file([attribution1, attribution2, attribution3])
      expect(notice).to include("THIRD-PARTY SOFTWARE NOTICES AND INFORMATION")
      expect(notice).to include("This software includes third-party components under the following licenses:")
    end

    it "groups attributions by license" do
      notice = described_class.generate_notice_file([attribution1, attribution2, attribution3])
      expect(notice).to include("MIT License")
      expect(notice).to include("Apache License 2.0")
    end

    it "sorts packages alphabetically within each license group" do
      notice = described_class.generate_notice_file([attribution1, attribution2, attribution3])
      axios_index = notice.index("axios")
      lodash_index = notice.index("lodash")
      expect(axios_index).to be < lodash_index
    end

    it "includes license text when any attribution requires license copy" do
      notice = described_class.generate_notice_file([attribution3])
      expect(notice).to include("License Text:")
      expect(notice).to include("Apache License 2.0 full text...")
    end

    it "includes generation timestamp" do
      notice = described_class.generate_notice_file([attribution1])
      expect(notice).to include("Generated at:")
    end

    it "handles empty attribution list" do
      notice = described_class.generate_notice_file([])
      expect(notice).to include("THIRD-PARTY SOFTWARE NOTICES AND INFORMATION")
    end

    it "handles attributions with no license" do
      attribution_no_license = create(:supply_chain_attribution,
                                     account: account,
                                     sbom_component: create(:supply_chain_sbom_component, sbom: sbom, account: account),
                                     license: nil,
                                     package_name: "unknown-package")
      notice = described_class.generate_notice_file([attribution_no_license])
      # When license is nil, the attribution won't have a license name, so it appears unlicensed
      expect(notice).to include("unknown-package")
    end
  end

  describe ".generate_for_sbom" do
    let!(:component1) do
      create(:supply_chain_sbom_component,
             sbom: sbom,
             account: account,
             name: "package1",
             version: "1.0.0")
    end

    let!(:component2) do
      create(:supply_chain_sbom_component,
             sbom: sbom,
             account: account,
             name: "package2",
             version: "2.0.0")
    end

    let!(:component3_with_attribution) do
      comp = create(:supply_chain_sbom_component,
                   sbom: sbom,
                   account: account,
                   name: "package3",
                   version: "3.0.0")
      create(:supply_chain_attribution, account: account, sbom_component: comp)
      comp
    end

    it "creates attributions for all components without existing attributions" do
      expect do
        described_class.generate_for_sbom(sbom)
      end.to change(described_class, :count).by(2)
    end

    it "does not create attribution for components that already have one" do
      described_class.generate_for_sbom(sbom)
      expect(component3_with_attribution.attribution).to be_present
      expect(described_class.where(sbom_component: component3_with_attribution).count).to eq(1)
    end

    it "calls create_for_component for each component" do
      allow(described_class).to receive(:create_for_component).and_call_original
      described_class.generate_for_sbom(sbom)
      expect(described_class).to have_received(:create_for_component).at_least(2).times
    end
  end

  describe ".create_for_component" do
    let(:mit) { create(:supply_chain_license, spdx_id: "MIT") }
    let(:component) do
      create(:supply_chain_sbom_component,
             sbom: sbom,
             account: account,
             name: "test-package",
             namespace: "@test",
             version: "1.2.3",
             license_spdx_id: "MIT")
    end

    before do
      mit # ensure license exists
    end

    it "creates an attribution for the component" do
      expect do
        described_class.create_for_component(component)
      end.to change(described_class, :count).by(1)
    end

    it "assigns the correct account" do
      attribution = described_class.create_for_component(component)
      expect(attribution.account).to eq(account)
    end

    it "assigns the correct sbom_component" do
      attribution = described_class.create_for_component(component)
      expect(attribution.sbom_component).to eq(component)
    end

    it "finds and assigns the license by SPDX ID" do
      attribution = described_class.create_for_component(component)
      expect(attribution.license).to eq(mit)
    end

    it "uses component's full_name for package_name" do
      attribution = described_class.create_for_component(component)
      expect(attribution.package_name).to eq(component.full_name)
    end

    it "uses component's version for package_version" do
      attribution = described_class.create_for_component(component)
      expect(attribution.package_version).to eq("1.2.3")
    end

    it "handles components without license_spdx_id" do
      component_no_license = create(:supply_chain_sbom_component,
                                   sbom: sbom,
                                   account: account,
                                   name: "no-license-package",
                                   version: "1.0.0",
                                   license_spdx_id: nil)

      attribution = described_class.create_for_component(component_no_license)
      expect(attribution.license).to be_nil
      expect(attribution.package_name).to eq(component_no_license.full_name)
    end

    it "handles components with unknown license_spdx_id" do
      component_unknown_license = create(:supply_chain_sbom_component,
                                        sbom: sbom,
                                        account: account,
                                        name: "unknown-license-package",
                                        version: "1.0.0",
                                        license_spdx_id: "UNKNOWN-LICENSE-123")

      attribution = described_class.create_for_component(component_unknown_license)
      expect(attribution.license).to be_nil
      expect(attribution.package_name).to eq(component_unknown_license.full_name)
    end
  end
end
