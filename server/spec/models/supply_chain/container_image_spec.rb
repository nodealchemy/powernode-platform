# frozen_string_literal: true

require "rails_helper"

RSpec.describe SupplyChain::ContainerImage, type: :model do
  let(:account) { create(:account) }

  describe "associations" do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:attestation).class_name("SupplyChain::Attestation").optional }
    it { is_expected.to belong_to(:base_image).class_name("SupplyChain::ContainerImage").optional }
    it { is_expected.to have_many(:vulnerability_scans).class_name("SupplyChain::VulnerabilityScan").dependent(:destroy) }
  end

  describe "validations" do
    subject { build(:supply_chain_container_image, account: account) }

    it { is_expected.to validate_presence_of(:registry) }
    it { is_expected.to validate_presence_of(:repository) }
    it { is_expected.to validate_presence_of(:tag) }
    it { is_expected.to validate_inclusion_of(:status).in_array(SupplyChain::ContainerImage::STATUSES) }
  end

  describe "#full_reference" do
    it "returns full image reference" do
      image = build(:supply_chain_container_image, registry: "gcr.io", repository: "project/app", tag: "v1.0.0")
      expect(image.full_reference).to eq("gcr.io/project/app:v1.0.0")
    end
  end

  describe "#quarantined?" do
    it "returns true when status is quarantined" do
      image = build(:supply_chain_container_image, status: "quarantined")
      expect(image.quarantined?).to be true
    end

    it "returns false for other statuses" do
      image = build(:supply_chain_container_image, status: "verified")
      expect(image.quarantined?).to be false
    end
  end

  describe "#verified?" do
    it "returns true when status is verified" do
      image = build(:supply_chain_container_image, status: "verified")
      expect(image.verified?).to be true
    end
  end

  describe "#total_vulnerabilities" do
    it "sums all vulnerability counts" do
      image = build(:supply_chain_container_image,
                    critical_vuln_count: 2,
                    high_vuln_count: 5,
                    medium_vuln_count: 10,
                    low_vuln_count: 20)
      expect(image.total_vulnerabilities).to eq(37)
    end
  end

  describe "#vulnerability_summary" do
    let(:image) do
      build(:supply_chain_container_image,
            critical_vuln_count: 1,
            high_vuln_count: 3,
            medium_vuln_count: 7,
            low_vuln_count: 15)
    end

    it "returns hash with vulnerability counts" do
      summary = image.vulnerability_summary
      expect(summary).to eq({
        critical: 1,
        high: 3,
        medium: 7,
        low: 15,
        total: 26
      })
    end
  end

  describe "#exceeds_vulnerability_threshold?" do
    let(:image) do
      build(:supply_chain_container_image,
            critical_vuln_count: 2,
            high_vuln_count: 5)
    end

    it "returns true when critical exceeds threshold" do
      expect(image.exceeds_vulnerability_threshold?(max_critical: 1)).to be true
    end

    it "returns true when high exceeds threshold" do
      expect(image.exceeds_vulnerability_threshold?(max_high: 3)).to be true
    end

    it "returns false when within thresholds" do
      expect(image.exceeds_vulnerability_threshold?(max_critical: 5, max_high: 10)).to be false
    end
  end
end
