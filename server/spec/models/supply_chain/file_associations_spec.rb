# frozen_string_literal: true

require "rails_helper"

RSpec.describe "SupplyChain File Associations", type: :model do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:file_storage) { create(:file_storage, account: account, is_default: true) }

  describe "SupplyChain::Vendor file_objects association" do
    let(:vendor) { create(:supply_chain_vendor, account: account) }

    it "has many file_objects" do
      expect(SupplyChain::Vendor.reflect_on_association(:file_objects)).to be_present
      expect(SupplyChain::Vendor.reflect_on_association(:file_objects).macro).to eq(:has_many)
    end

    it "associates with FileManagement::Object via polymorphic attachable" do
      association = SupplyChain::Vendor.reflect_on_association(:file_objects)
      expect(association.options[:as]).to eq(:attachable)
      expect(association.options[:class_name]).to eq("FileManagement::Object")
    end

    it "nullifies file_objects on destroy" do
      association = SupplyChain::Vendor.reflect_on_association(:file_objects)
      expect(association.options[:dependent]).to eq(:nullify)
    end

    it "can attach files with vendor_compliance category" do
      file_object = create(:file_object,
        account: account,
        storage: file_storage,
        uploaded_by: user,
        attachable: vendor,
        category: "vendor_compliance"
      )

      expect(vendor.file_objects).to include(file_object)
      expect(file_object.attachable).to eq(vendor)
      expect(file_object.category).to eq("vendor_compliance")
    end

    it "can attach files with vendor_assessment category" do
      file_object = create(:file_object,
        account: account,
        storage: file_storage,
        uploaded_by: user,
        attachable: vendor,
        category: "vendor_assessment"
      )

      expect(vendor.file_objects).to include(file_object)
      expect(file_object.category).to eq("vendor_assessment")
    end

    it "can attach files with vendor_certificate category" do
      file_object = create(:file_object,
        account: account,
        storage: file_storage,
        uploaded_by: user,
        attachable: vendor,
        category: "vendor_certificate"
      )

      expect(vendor.file_objects).to include(file_object)
      expect(file_object.category).to eq("vendor_certificate")
    end

    it "can have multiple files attached" do
      file1 = create(:file_object, account: account, storage: file_storage, uploaded_by: user, attachable: vendor, category: "vendor_compliance")
      file2 = create(:file_object, account: account, storage: file_storage, uploaded_by: user, attachable: vendor, category: "vendor_assessment")
      file3 = create(:file_object, account: account, storage: file_storage, uploaded_by: user, attachable: vendor, category: "vendor_certificate")

      expect(vendor.file_objects.count).to eq(3)
      expect(vendor.file_objects).to include(file1, file2, file3)
    end
  end

  describe "SupplyChain::Sbom file_objects association" do
    let(:sbom) { create(:supply_chain_sbom, account: account) }

    it "has many file_objects" do
      expect(SupplyChain::Sbom.reflect_on_association(:file_objects)).to be_present
      expect(SupplyChain::Sbom.reflect_on_association(:file_objects).macro).to eq(:has_many)
    end

    it "associates with FileManagement::Object via polymorphic attachable" do
      association = SupplyChain::Sbom.reflect_on_association(:file_objects)
      expect(association.options[:as]).to eq(:attachable)
      expect(association.options[:class_name]).to eq("FileManagement::Object")
    end

    it "nullifies file_objects on destroy" do
      association = SupplyChain::Sbom.reflect_on_association(:file_objects)
      expect(association.options[:dependent]).to eq(:nullify)
    end

    it "can attach files with sbom_export category" do
      file_object = create(:file_object,
        account: account,
        storage: file_storage,
        uploaded_by: user,
        attachable: sbom,
        category: "sbom_export"
      )

      expect(sbom.file_objects).to include(file_object)
      expect(file_object.attachable).to eq(sbom)
      expect(file_object.category).to eq("sbom_export")
    end

    it "can have multiple SBOM export files" do
      file1 = create(:file_object, account: account, storage: file_storage, uploaded_by: user, attachable: sbom, category: "sbom_export", filename: "sbom-cyclonedx.json")
      file2 = create(:file_object, account: account, storage: file_storage, uploaded_by: user, attachable: sbom, category: "sbom_export", filename: "sbom-spdx.json")

      expect(sbom.file_objects.count).to eq(2)
      expect(sbom.file_objects.pluck(:filename)).to contain_exactly("sbom-cyclonedx.json", "sbom-spdx.json")
    end
  end

  describe "SupplyChain::Attestation file_objects association" do
    let(:attestation) { create(:supply_chain_attestation, account: account) }

    it "has many file_objects" do
      expect(SupplyChain::Attestation.reflect_on_association(:file_objects)).to be_present
      expect(SupplyChain::Attestation.reflect_on_association(:file_objects).macro).to eq(:has_many)
    end

    it "associates with FileManagement::Object via polymorphic attachable" do
      association = SupplyChain::Attestation.reflect_on_association(:file_objects)
      expect(association.options[:as]).to eq(:attachable)
      expect(association.options[:class_name]).to eq("FileManagement::Object")
    end

    it "nullifies file_objects on destroy" do
      association = SupplyChain::Attestation.reflect_on_association(:file_objects)
      expect(association.options[:dependent]).to eq(:nullify)
    end

    it "can attach files with attestation_proof category" do
      file_object = create(:file_object,
        account: account,
        storage: file_storage,
        uploaded_by: user,
        attachable: attestation,
        category: "attestation_proof"
      )

      expect(attestation.file_objects).to include(file_object)
      expect(file_object.attachable).to eq(attestation)
      expect(file_object.category).to eq("attestation_proof")
    end

    it "can have multiple attestation proof files" do
      file1 = create(:file_object, account: account, storage: file_storage, uploaded_by: user, attachable: attestation, category: "attestation_proof", filename: "attestation.sig")
      file2 = create(:file_object, account: account, storage: file_storage, uploaded_by: user, attachable: attestation, category: "attestation_proof", filename: "attestation.bundle")

      expect(attestation.file_objects.count).to eq(2)
    end
  end

  describe "SupplyChain::ContainerImage file_objects association" do
    let(:container_image) { create(:supply_chain_container_image, account: account) }

    it "has many file_objects" do
      expect(SupplyChain::ContainerImage.reflect_on_association(:file_objects)).to be_present
      expect(SupplyChain::ContainerImage.reflect_on_association(:file_objects).macro).to eq(:has_many)
    end

    it "associates with FileManagement::Object via polymorphic attachable" do
      association = SupplyChain::ContainerImage.reflect_on_association(:file_objects)
      expect(association.options[:as]).to eq(:attachable)
      expect(association.options[:class_name]).to eq("FileManagement::Object")
    end

    it "nullifies file_objects on destroy" do
      association = SupplyChain::ContainerImage.reflect_on_association(:file_objects)
      expect(association.options[:dependent]).to eq(:nullify)
    end

    it "can attach files with supply_chain_scan_report category" do
      file_object = create(:file_object,
        account: account,
        storage: file_storage,
        uploaded_by: user,
        attachable: container_image,
        category: "supply_chain_scan_report"
      )

      expect(container_image.file_objects).to include(file_object)
      expect(file_object.attachable).to eq(container_image)
      expect(file_object.category).to eq("supply_chain_scan_report")
    end

    it "can have multiple scan report files" do
      file1 = create(:file_object, account: account, storage: file_storage, uploaded_by: user, attachable: container_image, category: "supply_chain_scan_report", filename: "trivy-scan.json")
      file2 = create(:file_object, account: account, storage: file_storage, uploaded_by: user, attachable: container_image, category: "supply_chain_scan_report", filename: "grype-scan.json")

      expect(container_image.file_objects.count).to eq(2)
    end
  end

  describe "FileManagement::Object category validation" do
    it "accepts sbom_export category" do
      file_object = build(:file_object, account: account, storage: file_storage, uploaded_by: user, category: "sbom_export")
      expect(file_object).to be_valid
    end

    it "accepts attestation_proof category" do
      file_object = build(:file_object, account: account, storage: file_storage, uploaded_by: user, category: "attestation_proof")
      expect(file_object).to be_valid
    end

    it "accepts supply_chain_scan_report category" do
      file_object = build(:file_object, account: account, storage: file_storage, uploaded_by: user, category: "supply_chain_scan_report")
      expect(file_object).to be_valid
    end

    it "accepts vendor_compliance category" do
      file_object = build(:file_object, account: account, storage: file_storage, uploaded_by: user, category: "vendor_compliance")
      expect(file_object).to be_valid
    end

    it "accepts vendor_assessment category" do
      file_object = build(:file_object, account: account, storage: file_storage, uploaded_by: user, category: "vendor_assessment")
      expect(file_object).to be_valid
    end

    it "accepts vendor_certificate category" do
      file_object = build(:file_object, account: account, storage: file_storage, uploaded_by: user, category: "vendor_certificate")
      expect(file_object).to be_valid
    end

    it "rejects invalid category" do
      file_object = build(:file_object, account: account, storage: file_storage, uploaded_by: user, category: "invalid_category")
      expect(file_object).not_to be_valid
      expect(file_object.errors[:category]).to be_present
    end

    it "still accepts existing categories" do
      %w[user_upload workflow_output ai_generated temp system import page_content].each do |category|
        file_object = build(:file_object, account: account, storage: file_storage, uploaded_by: user, category: category)
        expect(file_object).to be_valid, "Expected #{category} to be valid"
      end
    end
  end

  describe "file attachment lifecycle" do
    let(:vendor) { create(:supply_chain_vendor, account: account) }

    it "preserves file when vendor is destroyed (nullifies association)" do
      file_object = create(:file_object,
        account: account,
        storage: file_storage,
        uploaded_by: user,
        attachable: vendor,
        category: "vendor_compliance"
      )

      expect { vendor.destroy }.not_to change { FileManagement::Object.count }

      file_object.reload
      expect(file_object.attachable).to be_nil
      expect(file_object.attachable_type).to be_nil
      expect(file_object.attachable_id).to be_nil
    end

    it "allows re-attaching orphaned file to another entity" do
      file_object = create(:file_object,
        account: account,
        storage: file_storage,
        uploaded_by: user,
        attachable: vendor,
        category: "vendor_compliance"
      )

      vendor.destroy
      file_object.reload

      new_vendor = create(:supply_chain_vendor, account: account)
      file_object.update!(attachable: new_vendor)

      expect(file_object.attachable).to eq(new_vendor)
      expect(new_vendor.file_objects).to include(file_object)
    end
  end
end
