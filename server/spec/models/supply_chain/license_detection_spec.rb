# frozen_string_literal: true

require "rails_helper"

RSpec.describe SupplyChain::LicenseDetection, type: :model do
  let(:account) { create(:account) }
  let(:sbom) { create(:supply_chain_sbom, account: account) }
  let(:sbom_component) { create(:supply_chain_sbom_component, sbom: sbom, account: account) }
  let(:license) { create(:supply_chain_license, spdx_id: "MIT", name: "MIT License") }

  describe "associations" do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:sbom_component).class_name("SupplyChain::SbomComponent") }
    it { is_expected.to belong_to(:license).class_name("SupplyChain::License").optional }
  end

  describe "validations" do
    subject { build(:supply_chain_license_detection, account: account, sbom_component: sbom_component) }

    it { is_expected.to validate_presence_of(:detection_source) }
    it { is_expected.to validate_inclusion_of(:detection_source).in_array(SupplyChain::LicenseDetection::DETECTION_SOURCES) }
    it { is_expected.to validate_numericality_of(:confidence_score).is_greater_than_or_equal_to(0).is_less_than_or_equal_to(1) }

    it "accepts valid detection sources" do
      SupplyChain::LicenseDetection::DETECTION_SOURCES.each do |source|
        detection = build(:supply_chain_license_detection, detection_source: source, account: account, sbom_component: sbom_component)
        expect(detection).to be_valid
      end
    end

    it "rejects invalid detection sources" do
      detection = build(:supply_chain_license_detection, detection_source: "invalid", account: account, sbom_component: sbom_component)
      expect(detection).not_to be_valid
      expect(detection.errors[:detection_source]).to include("is not included in the list")
    end

    it "accepts confidence scores between 0 and 1" do
      detection = build(:supply_chain_license_detection, confidence_score: 0.5, account: account, sbom_component: sbom_component)
      expect(detection).to be_valid
    end

    it "accepts confidence score of 0" do
      detection = build(:supply_chain_license_detection, confidence_score: 0, account: account, sbom_component: sbom_component)
      expect(detection).to be_valid
    end

    it "accepts confidence score of 1" do
      detection = build(:supply_chain_license_detection, confidence_score: 1, account: account, sbom_component: sbom_component)
      expect(detection).to be_valid
    end

    it "rejects confidence scores less than 0" do
      detection = build(:supply_chain_license_detection, confidence_score: -0.1, account: account, sbom_component: sbom_component)
      expect(detection).not_to be_valid
      expect(detection.errors[:confidence_score]).to be_present
    end

    it "rejects confidence scores greater than 1" do
      detection = build(:supply_chain_license_detection, confidence_score: 1.1, account: account, sbom_component: sbom_component)
      expect(detection).not_to be_valid
      expect(detection.errors[:confidence_score]).to be_present
    end
  end

  describe "scopes" do
    let!(:manifest_detection) { create(:supply_chain_license_detection, detection_source: "manifest", account: account, sbom_component: sbom_component) }
    let!(:file_detection) { create(:supply_chain_license_detection, detection_source: "file", account: account, sbom_component: sbom_component) }
    let!(:api_detection) { create(:supply_chain_license_detection, detection_source: "api", account: account, sbom_component: sbom_component) }
    let!(:ai_detection) { create(:supply_chain_license_detection, detection_source: "ai", account: account, sbom_component: sbom_component) }
    let!(:manual_detection) { create(:supply_chain_license_detection, detection_source: "manual", account: account, sbom_component: sbom_component) }
    let!(:primary_detection) { create(:supply_chain_license_detection, :primary, account: account, sbom_component: sbom_component) }
    let!(:non_primary_detection) { create(:supply_chain_license_detection, is_primary: false, account: account, sbom_component: sbom_component) }
    let!(:needs_review_detection) { create(:supply_chain_license_detection, :needs_review, account: account, sbom_component: sbom_component) }
    let!(:reviewed_detection) { create(:supply_chain_license_detection, requires_review: false, account: account, sbom_component: sbom_component) }
    let!(:high_confidence_detection) { create(:supply_chain_license_detection, :high_confidence, account: account, sbom_component: sbom_component) }
    let!(:low_confidence_detection) { create(:supply_chain_license_detection, confidence_score: 0.3, account: account, sbom_component: sbom_component) }
    let!(:old_detection) { create(:supply_chain_license_detection, account: account, sbom_component: sbom_component, created_at: 1.week.ago) }

    describe ".by_source" do
      it "filters detections by source" do
        expect(described_class.by_source("manifest")).to include(manifest_detection)
        expect(described_class.by_source("manifest")).not_to include(file_detection)
      end
    end

    describe ".manifest_detections" do
      it "returns only manifest detections" do
        expect(described_class.manifest_detections).to include(manifest_detection)
        expect(described_class.manifest_detections).not_to include(file_detection, api_detection, ai_detection, manual_detection)
      end
    end

    describe ".file_detections" do
      it "returns only file detections" do
        expect(described_class.file_detections).to include(file_detection)
        expect(described_class.file_detections).not_to include(manifest_detection, api_detection, ai_detection, manual_detection)
      end
    end

    describe ".api_detections" do
      it "returns only api detections" do
        expect(described_class.api_detections).to include(api_detection)
        expect(described_class.api_detections).not_to include(manifest_detection, file_detection, ai_detection, manual_detection)
      end
    end

    describe ".ai_detections" do
      it "returns only ai detections" do
        expect(described_class.ai_detections).to include(ai_detection)
        expect(described_class.ai_detections).not_to include(manifest_detection, file_detection, api_detection, manual_detection)
      end
    end

    describe ".manual_detections" do
      it "returns only manual detections" do
        expect(described_class.manual_detections).to include(manual_detection)
        expect(described_class.manual_detections).not_to include(manifest_detection, file_detection, api_detection, ai_detection)
      end
    end

    describe ".primary" do
      it "returns only primary detections" do
        expect(described_class.primary).to include(primary_detection)
        expect(described_class.primary).not_to include(non_primary_detection)
      end
    end

    describe ".needs_review" do
      it "returns only detections requiring review" do
        expect(described_class.needs_review).to include(needs_review_detection)
        expect(described_class.needs_review).not_to include(reviewed_detection)
      end
    end

    describe ".high_confidence" do
      it "returns detections with confidence >= 0.9" do
        expect(described_class.high_confidence).to include(high_confidence_detection)
        expect(described_class.high_confidence).not_to include(low_confidence_detection)
      end
    end

    describe ".low_confidence" do
      it "returns detections with confidence < 0.5" do
        expect(described_class.low_confidence).to include(low_confidence_detection)
        expect(described_class.low_confidence).not_to include(high_confidence_detection)
      end
    end

    describe ".for_component" do
      let(:other_component) { create(:supply_chain_sbom_component, sbom: sbom, account: account) }
      let!(:other_detection) { create(:supply_chain_license_detection, account: account, sbom_component: other_component) }

      it "filters detections by component" do
        expect(described_class.for_component(sbom_component.id)).to include(manifest_detection)
        expect(described_class.for_component(sbom_component.id)).not_to include(other_detection)
      end
    end

    describe ".recent" do
      it "orders detections by created_at descending" do
        ordered = described_class.recent
        expect(ordered.first.created_at).to be >= ordered.last.created_at
      end
    end
  end

  describe "detection source predicate methods" do
    describe "#manifest?" do
      it "returns true for manifest detections" do
        detection = build(:supply_chain_license_detection, detection_source: "manifest")
        expect(detection.manifest?).to be true
      end

      it "returns false for non-manifest detections" do
        detection = build(:supply_chain_license_detection, detection_source: "file")
        expect(detection.manifest?).to be false
      end
    end

    describe "#file?" do
      it "returns true for file detections" do
        detection = build(:supply_chain_license_detection, detection_source: "file")
        expect(detection.file?).to be true
      end

      it "returns false for non-file detections" do
        detection = build(:supply_chain_license_detection, detection_source: "manifest")
        expect(detection.file?).to be false
      end
    end

    describe "#api?" do
      it "returns true for api detections" do
        detection = build(:supply_chain_license_detection, detection_source: "api")
        expect(detection.api?).to be true
      end

      it "returns false for non-api detections" do
        detection = build(:supply_chain_license_detection, detection_source: "manifest")
        expect(detection.api?).to be false
      end
    end

    describe "#ai?" do
      it "returns true for ai detections" do
        detection = build(:supply_chain_license_detection, detection_source: "ai")
        expect(detection.ai?).to be true
      end

      it "returns false for non-ai detections" do
        detection = build(:supply_chain_license_detection, detection_source: "manifest")
        expect(detection.ai?).to be false
      end
    end

    describe "#manual?" do
      it "returns true for manual detections" do
        detection = build(:supply_chain_license_detection, detection_source: "manual")
        expect(detection.manual?).to be true
      end

      it "returns false for non-manual detections" do
        detection = build(:supply_chain_license_detection, detection_source: "manifest")
        expect(detection.manual?).to be false
      end
    end
  end

  describe "status predicate methods" do
    describe "#primary?" do
      it "returns true when is_primary is true" do
        detection = build(:supply_chain_license_detection, is_primary: true)
        expect(detection.primary?).to be true
      end

      it "returns false when is_primary is false" do
        detection = build(:supply_chain_license_detection, is_primary: false)
        expect(detection.primary?).to be false
      end
    end

    describe "#needs_review?" do
      it "returns true when requires_review is true" do
        detection = build(:supply_chain_license_detection, requires_review: true)
        expect(detection.needs_review?).to be true
      end

      it "returns false when requires_review is false" do
        detection = build(:supply_chain_license_detection, requires_review: false)
        expect(detection.needs_review?).to be false
      end
    end

    describe "#high_confidence?" do
      it "returns true when confidence_score >= 0.9" do
        detection = build(:supply_chain_license_detection, confidence_score: 0.95)
        expect(detection.high_confidence?).to be true
      end

      it "returns true when confidence_score is exactly 0.9" do
        detection = build(:supply_chain_license_detection, confidence_score: 0.9)
        expect(detection.high_confidence?).to be true
      end

      it "returns false when confidence_score < 0.9" do
        detection = build(:supply_chain_license_detection, confidence_score: 0.85)
        expect(detection.high_confidence?).to be false
      end
    end

    describe "#low_confidence?" do
      it "returns true when confidence_score < 0.5" do
        detection = build(:supply_chain_license_detection, confidence_score: 0.3)
        expect(detection.low_confidence?).to be true
      end

      it "returns false when confidence_score >= 0.5" do
        detection = build(:supply_chain_license_detection, confidence_score: 0.5)
        expect(detection.low_confidence?).to be false
      end

      it "returns false when confidence_score is exactly 0.5" do
        detection = build(:supply_chain_license_detection, confidence_score: 0.5)
        expect(detection.low_confidence?).to be false
      end
    end

    describe "#resolved?" do
      it "returns true when license is present" do
        detection = build(:supply_chain_license_detection, license: license)
        expect(detection.resolved?).to be true
      end

      it "returns false when license is nil" do
        detection = build(:supply_chain_license_detection, license: nil)
        expect(detection.resolved?).to be false
      end
    end
  end

  describe "#effective_license_id" do
    it "returns license spdx_id when license is present" do
      detection = build(:supply_chain_license_detection, license: license, detected_license_id: "Apache-2.0")
      expect(detection.effective_license_id).to eq("MIT")
    end

    it "returns detected_license_id when license is nil" do
      detection = build(:supply_chain_license_detection, license: nil, detected_license_id: "Apache-2.0")
      expect(detection.effective_license_id).to eq("Apache-2.0")
    end

    it "returns nil when both license and detected_license_id are nil" do
      detection = build(:supply_chain_license_detection, license: nil, detected_license_id: nil)
      expect(detection.effective_license_id).to be_nil
    end
  end

  describe "#effective_license_name" do
    it "returns license name when license is present" do
      detection = build(:supply_chain_license_detection, license: license, detected_license_name: "Apache License 2.0")
      expect(detection.effective_license_name).to eq("MIT License")
    end

    it "returns detected_license_name when license is nil" do
      detection = build(:supply_chain_license_detection, license: nil, detected_license_name: "Apache License 2.0")
      expect(detection.effective_license_name).to eq("Apache License 2.0")
    end

    it "returns nil when both license and detected_license_name are nil" do
      detection = build(:supply_chain_license_detection, license: nil, detected_license_name: nil)
      expect(detection.effective_license_name).to be_nil
    end
  end

  describe "#mark_as_primary!" do
    let!(:existing_primary) { create(:supply_chain_license_detection, :primary, account: account, sbom_component: sbom_component) }
    let!(:detection) { create(:supply_chain_license_detection, is_primary: false, account: account, sbom_component: sbom_component, license: license) }

    it "sets is_primary to true" do
      detection.mark_as_primary!
      expect(detection.reload.is_primary).to be true
    end

    it "unsets is_primary on other detections for the same component" do
      detection.mark_as_primary!
      expect(existing_primary.reload.is_primary).to be false
    end

    it "updates component license when detection has license" do
      detection.mark_as_primary!
      sbom_component.reload
      expect(sbom_component.license_spdx_id).to eq(license.spdx_id)
      expect(sbom_component.license_name).to eq(license.name)
    end

    it "works within a transaction" do
      expect { detection.mark_as_primary! }.not_to raise_error
      expect(detection.reload.is_primary).to be true
    end
  end

  describe "#mark_needs_review!" do
    let(:detection) { create(:supply_chain_license_detection, requires_review: false, account: account, sbom_component: sbom_component, metadata: {}) }

    it "sets requires_review to true" do
      detection.mark_needs_review!("Low confidence score")
      expect(detection.reload.requires_review).to be true
    end

    it "adds review reason to metadata" do
      detection.mark_needs_review!("Low confidence score")
      expect(detection.reload.metadata["review_reason"]).to eq("Low confidence score")
    end

    it "merges with existing metadata" do
      detection.update!(metadata: { "existing_key" => "existing_value" })
      detection.mark_needs_review!("Conflicting detection")
      expect(detection.reload.metadata["existing_key"]).to eq("existing_value")
      expect(detection.reload.metadata["review_reason"]).to eq("Conflicting detection")
    end

    it "works without reason" do
      detection.mark_needs_review!
      expect(detection.reload.requires_review).to be true
      expect(detection.reload.metadata["review_reason"]).to be_nil
    end
  end

  describe "#clear_review_flag!" do
    let(:detection) { create(:supply_chain_license_detection, :needs_review, account: account, sbom_component: sbom_component) }

    it "sets requires_review to false" do
      detection.clear_review_flag!
      expect(detection.reload.requires_review).to be false
    end
  end

  describe "#summary" do
    let(:detection) do
      create(:supply_chain_license_detection,
             account: account,
             sbom_component: sbom_component,
             license: license,
             detected_license_id: "MIT",
             detected_license_name: "MIT License",
             detection_source: "manifest",
             confidence_score: 0.95,
             is_primary: true,
             requires_review: false,
             file_path: "package.json")
    end

    it "returns a summary hash with expected keys" do
      summary = detection.summary

      expect(summary).to include(
        :id,
        :sbom_component_id,
        :detected_license_id,
        :detected_license_name,
        :resolved_license_id,
        :detection_source,
        :confidence_score,
        :is_primary,
        :requires_review,
        :file_path,
        :created_at
      )
    end

    it "includes correct values" do
      summary = detection.summary

      expect(summary[:id]).to eq(detection.id)
      expect(summary[:sbom_component_id]).to eq(sbom_component.id)
      expect(summary[:detected_license_id]).to eq("MIT")
      expect(summary[:detected_license_name]).to eq("MIT License")
      expect(summary[:resolved_license_id]).to eq("MIT")
      expect(summary[:detection_source]).to eq("manifest")
      expect(summary[:confidence_score]).to eq(0.95)
      expect(summary[:is_primary]).to be true
      expect(summary[:requires_review]).to be false
      expect(summary[:file_path]).to eq("package.json")
    end

    it "handles nil license" do
      # Must also clear detected_license_id to prevent resolve_license callback from re-resolving
      detection.update!(license: nil, detected_license_id: nil)
      summary = detection.summary

      expect(summary[:resolved_license_id]).to be_nil
    end
  end

  describe "callbacks" do
    describe "#sanitize_jsonb_fields" do
      it "initializes ai_interpretation as empty hash when nil" do
        detection = create(:supply_chain_license_detection, account: account, sbom_component: sbom_component, ai_interpretation: nil)
        expect(detection.ai_interpretation).to eq({})
      end

      it "initializes metadata as empty hash when nil" do
        detection = create(:supply_chain_license_detection, account: account, sbom_component: sbom_component, metadata: nil)
        expect(detection.metadata).to eq({})
      end

      it "preserves existing ai_interpretation" do
        detection = create(:supply_chain_license_detection, account: account, sbom_component: sbom_component, ai_interpretation: { "key" => "value" })
        expect(detection.ai_interpretation).to eq({ "key" => "value" })
      end

      it "preserves existing metadata" do
        detection = create(:supply_chain_license_detection, account: account, sbom_component: sbom_component, metadata: { "key" => "value" })
        expect(detection.metadata).to eq({ "key" => "value" })
      end
    end

    describe "#resolve_license" do
      let!(:apache_license) { create(:supply_chain_license, spdx_id: "Apache-2.0", name: "Apache License 2.0") }

      it "resolves license from detected_license_id when license is nil" do
        detection = create(:supply_chain_license_detection,
                          account: account,
                          sbom_component: sbom_component,
                          license: nil,
                          detected_license_id: "Apache-2.0")
        expect(detection.license).to eq(apache_license)
      end

      it "does not resolve license when license is already set" do
        detection = create(:supply_chain_license_detection,
                          account: account,
                          sbom_component: sbom_component,
                          license: license,
                          detected_license_id: "Apache-2.0")
        expect(detection.license).to eq(license)
        expect(detection.license).not_to eq(apache_license)
      end

      it "does not resolve license when detected_license_id is nil" do
        detection = create(:supply_chain_license_detection,
                          account: account,
                          sbom_component: sbom_component,
                          license: nil,
                          detected_license_id: nil)
        expect(detection.license).to be_nil
      end

      it "handles unknown license IDs gracefully" do
        detection = create(:supply_chain_license_detection,
                          account: account,
                          sbom_component: sbom_component,
                          license: nil,
                          detected_license_id: "Unknown-License")
        expect(detection.license).to be_nil
      end
    end

    describe "#update_component_license" do
      let(:detection) { create(:supply_chain_license_detection, account: account, sbom_component: sbom_component, license: license, is_primary: false) }

      it "updates component license when marked as primary" do
        detection.update!(is_primary: true)
        sbom_component.reload
        expect(sbom_component.license_spdx_id).to eq(license.spdx_id)
        expect(sbom_component.license_name).to eq(license.name)
      end

      it "updates component license when license changes on primary detection" do
        detection.update!(is_primary: true)
        new_license = create(:supply_chain_license, spdx_id: "GPL-3.0", name: "GNU General Public License v3.0")
        detection.update!(license: new_license)
        sbom_component.reload
        expect(sbom_component.license_spdx_id).to eq(new_license.spdx_id)
        expect(sbom_component.license_name).to eq(new_license.name)
      end

      it "does not update component when not primary" do
        original_spdx = sbom_component.license_spdx_id
        detection.update!(license: license)
        sbom_component.reload
        expect(sbom_component.license_spdx_id).to eq(original_spdx)
      end

      it "does not update component when license is nil" do
        detection.update!(is_primary: true, license: nil)
        sbom_component.reload
        # Should not raise an error, just skip the update
        expect(sbom_component).to be_present
      end

      it "only triggers when is_primary or license_id changes" do
        detection.update!(is_primary: true)
        sbom_component.reload
        initial_spdx = sbom_component.license_spdx_id

        # Update a different field
        detection.update!(confidence_score: 0.8)
        sbom_component.reload
        expect(sbom_component.license_spdx_id).to eq(initial_spdx)
      end
    end
  end
end
