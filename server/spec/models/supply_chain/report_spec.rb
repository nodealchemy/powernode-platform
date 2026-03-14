# frozen_string_literal: true

require "rails_helper"

RSpec.describe SupplyChain::Report, type: :model do
  let(:account) { create(:account) }
  let(:sbom) { create(:supply_chain_sbom, account: account) }
  let(:user) { create(:user, account: account) }

  describe "associations" do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:sbom).class_name("SupplyChain::Sbom").optional }
    it { is_expected.to belong_to(:created_by).class_name("User").optional }
  end

  describe "validations" do
    subject { build(:supply_chain_report, account: account) }

    it { is_expected.to validate_presence_of(:report_type) }
    it { is_expected.to validate_inclusion_of(:report_type).in_array(SupplyChain::Report::REPORT_TYPES) }
    it { is_expected.to validate_presence_of(:format) }
    it { is_expected.to validate_inclusion_of(:format).in_array(SupplyChain::Report::FORMATS) }
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:status) }
    it { is_expected.to validate_inclusion_of(:status).in_array(SupplyChain::Report::STATUSES) }
  end

  describe "scopes" do
    let!(:pending_report) { create(:supply_chain_report, :pending, account: account) }
    let!(:generating_report) { create(:supply_chain_report, :generating, account: account) }
    let!(:completed_report) { create(:supply_chain_report, :completed, account: account) }
    let!(:failed_report) { create(:supply_chain_report, :failed, account: account) }
    let!(:expired_report) { create(:supply_chain_report, :expired, account: account) }
    let!(:sbom_export_report) { create(:supply_chain_report, :sbom_export, :completed, account: account) }
    let!(:vulnerability_report) { create(:supply_chain_report, :vulnerability_report, :completed, account: account) }
    let!(:license_report) { create(:supply_chain_report, :license_report, :completed, account: account) }
    let!(:attribution_report) { create(:supply_chain_report, :attribution, :completed, account: account) }
    let!(:compliance_report) { create(:supply_chain_report, :compliance_summary, :completed, account: account) }
    let!(:expiring_soon_report) { create(:supply_chain_report, :completed, account: account, expires_at: 5.days.from_now) }
    let!(:pdf_report) { create(:supply_chain_report, :completed, account: account, format: "pdf") }
    let!(:json_report) { create(:supply_chain_report, :completed, account: account, format: "json") }

    describe ".by_status" do
      it "filters by pending status" do
        expect(described_class.by_status("pending")).to include(pending_report)
        expect(described_class.by_status("pending")).not_to include(completed_report)
      end
    end

    describe ".pending" do
      it "returns only pending reports" do
        expect(described_class.pending).to include(pending_report)
        expect(described_class.pending).not_to include(completed_report)
      end
    end

    describe ".generating" do
      it "returns only generating reports" do
        expect(described_class.generating).to include(generating_report)
        expect(described_class.generating).not_to include(completed_report)
      end
    end

    describe ".completed" do
      it "returns only completed reports" do
        expect(described_class.completed).to include(completed_report)
        expect(described_class.completed).not_to include(pending_report)
      end
    end

    describe ".failed" do
      it "returns only failed reports" do
        expect(described_class.failed).to include(failed_report)
        expect(described_class.failed).not_to include(completed_report)
      end
    end

    describe ".expired" do
      it "returns only expired reports" do
        expect(described_class.expired).to include(expired_report)
        expect(described_class.expired).not_to include(completed_report)
      end
    end

    describe ".by_type" do
      it "filters by report type" do
        expect(described_class.by_type("sbom_export")).to include(sbom_export_report)
        expect(described_class.by_type("sbom_export")).not_to include(vulnerability_report)
      end
    end

    describe ".by_format" do
      it "filters by format" do
        expect(described_class.by_format("pdf")).to include(pdf_report)
        expect(described_class.by_format("pdf")).not_to include(json_report)
      end
    end

    describe ".sbom_exports" do
      it "returns only sbom_export reports" do
        expect(described_class.sbom_exports).to include(sbom_export_report)
        expect(described_class.sbom_exports).not_to include(vulnerability_report)
      end
    end

    describe ".vulnerability_reports" do
      it "returns only vulnerability reports" do
        expect(described_class.vulnerability_reports).to include(vulnerability_report)
        expect(described_class.vulnerability_reports).not_to include(sbom_export_report)
      end
    end

    describe ".license_reports" do
      it "returns only license reports" do
        expect(described_class.license_reports).to include(license_report)
        expect(described_class.license_reports).not_to include(vulnerability_report)
      end
    end

    describe ".attribution_reports" do
      it "returns only attribution reports" do
        expect(described_class.attribution_reports).to include(attribution_report)
        expect(described_class.attribution_reports).not_to include(license_report)
      end
    end

    describe ".compliance_reports" do
      it "returns only compliance summary reports" do
        expect(described_class.compliance_reports).to include(compliance_report)
        expect(described_class.compliance_reports).not_to include(attribution_report)
      end
    end

    describe ".available" do
      it "returns completed reports that are not expired" do
        expect(described_class.available).to include(completed_report)
        expect(described_class.available).not_to include(expired_report)
        expect(described_class.available).not_to include(pending_report)
      end

      it "excludes reports with past expiration dates" do
        past_expired = create(:supply_chain_report, :completed, account: account, expires_at: 1.day.ago)
        expect(described_class.available).not_to include(past_expired)
      end
    end

    describe ".expiring_soon" do
      it "returns reports expiring within specified days" do
        expect(described_class.expiring_soon(7)).to include(expiring_soon_report)
        expect(described_class.expiring_soon(7)).not_to include(completed_report)
      end

      it "uses default 7 days if not specified" do
        expect(described_class.expiring_soon).to include(expiring_soon_report)
      end
    end

    describe ".recent" do
      it "orders by created_at descending" do
        recent_reports = described_class.recent.limit(2)
        expect(recent_reports.first.created_at).to be >= recent_reports.last.created_at
      end
    end
  end

  describe "status predicates" do
    describe "#pending?" do
      it "returns true for pending status" do
        report = build(:supply_chain_report, :pending)
        expect(report.pending?).to be true
      end

      it "returns false for non-pending status" do
        report = build(:supply_chain_report, :completed)
        expect(report.pending?).to be false
      end
    end

    describe "#generating?" do
      it "returns true for generating status" do
        report = build(:supply_chain_report, :generating)
        expect(report.generating?).to be true
      end

      it "returns false for non-generating status" do
        report = build(:supply_chain_report, :pending)
        expect(report.generating?).to be false
      end
    end

    describe "#completed?" do
      it "returns true for completed status" do
        report = build(:supply_chain_report, :completed)
        expect(report.completed?).to be true
      end

      it "returns false for non-completed status" do
        report = build(:supply_chain_report, :pending)
        expect(report.completed?).to be false
      end
    end

    describe "#failed?" do
      it "returns true for failed status" do
        report = build(:supply_chain_report, :failed)
        expect(report.failed?).to be true
      end

      it "returns false for non-failed status" do
        report = build(:supply_chain_report, :pending)
        expect(report.failed?).to be false
      end
    end

    describe "#expired?" do
      it "returns true for expired status" do
        report = build(:supply_chain_report, :expired)
        expect(report.expired?).to be true
      end

      it "returns true when expires_at is in the past" do
        report = build(:supply_chain_report, :completed, expires_at: 1.day.ago)
        expect(report.expired?).to be true
      end

      it "returns false for completed status with future expiry" do
        report = build(:supply_chain_report, :completed, expires_at: 30.days.from_now)
        expect(report.expired?).to be false
      end

      it "returns false when expires_at is nil" do
        report = build(:supply_chain_report, :completed, expires_at: nil)
        expect(report.expired?).to be false
      end
    end
  end

  describe "availability predicates" do
    describe "#available?" do
      it "returns true for completed and not expired" do
        report = build(:supply_chain_report, :completed, expires_at: 30.days.from_now)
        expect(report.available?).to be true
      end

      it "returns false for pending reports" do
        report = build(:supply_chain_report, :pending)
        expect(report.available?).to be false
      end

      it "returns false for expired reports" do
        report = build(:supply_chain_report, :completed, expires_at: 1.day.ago)
        expect(report.available?).to be false
      end
    end

    describe "#downloadable?" do
      it "returns true when available and file_path is present" do
        report = build(:supply_chain_report, :completed, file_path: "/tmp/report.pdf")
        expect(report.downloadable?).to be true
      end

      it "returns false when file_path is nil" do
        report = build(:supply_chain_report, :completed, file_path: nil)
        expect(report.downloadable?).to be false
      end

      it "returns false when not available" do
        report = build(:supply_chain_report, :pending, file_path: "/tmp/report.pdf")
        expect(report.downloadable?).to be false
      end
    end
  end

  describe "report type predicates" do
    describe "#sbom_export?" do
      it "returns true for sbom_export type" do
        report = build(:supply_chain_report, :sbom_export)
        expect(report.sbom_export?).to be true
      end

      it "returns false for other types" do
        report = build(:supply_chain_report, :vulnerability_report)
        expect(report.sbom_export?).to be false
      end
    end

    describe "#vulnerability_report?" do
      it "returns true for vulnerability_report type" do
        report = build(:supply_chain_report, :vulnerability_report)
        expect(report.vulnerability_report?).to be true
      end

      it "returns false for other types" do
        report = build(:supply_chain_report, :sbom_export)
        expect(report.vulnerability_report?).to be false
      end
    end

    describe "#license_report?" do
      it "returns true for license_report type" do
        report = build(:supply_chain_report, :license_report)
        expect(report.license_report?).to be true
      end

      it "returns false for other types" do
        report = build(:supply_chain_report, :sbom_export)
        expect(report.license_report?).to be false
      end
    end

    describe "#attribution?" do
      it "returns true for attribution type" do
        report = build(:supply_chain_report, :attribution)
        expect(report.attribution?).to be true
      end

      it "returns false for other types" do
        report = build(:supply_chain_report, :license_report)
        expect(report.attribution?).to be false
      end
    end

    describe "#compliance_summary?" do
      it "returns true for compliance_summary type" do
        report = build(:supply_chain_report, :compliance_summary)
        expect(report.compliance_summary?).to be true
      end

      it "returns false for other types" do
        report = build(:supply_chain_report, :attribution)
        expect(report.compliance_summary?).to be false
      end
    end

    describe "#vendor_assessment?" do
      it "returns true for vendor_assessment type" do
        report = build(:supply_chain_report, :vendor_assessment)
        expect(report.vendor_assessment?).to be true
      end

      it "returns false for other types" do
        report = build(:supply_chain_report, :compliance_summary)
        expect(report.vendor_assessment?).to be false
      end
    end
  end

  describe "#formatted_size" do
    it "returns nil when file_size_bytes is nil" do
      report = build(:supply_chain_report, file_size_bytes: nil)
      expect(report.formatted_size).to be_nil
    end

    it "formats bytes for sizes under 1KB" do
      report = build(:supply_chain_report, file_size_bytes: 512)
      expect(report.formatted_size).to eq("512 bytes")
    end

    it "formats KB for sizes between 1KB and 1MB" do
      report = build(:supply_chain_report, file_size_bytes: 2048)
      expect(report.formatted_size).to eq("2.0 KB")
    end

    it "formats KB with decimals" do
      report = build(:supply_chain_report, file_size_bytes: 1536)
      expect(report.formatted_size).to eq("1.5 KB")
    end

    it "formats MB for sizes over 1MB" do
      report = build(:supply_chain_report, file_size_bytes: 2_097_152)
      expect(report.formatted_size).to eq("2.0 MB")
    end

    it "formats MB with decimals" do
      report = build(:supply_chain_report, file_size_bytes: 5_242_880)
      expect(report.formatted_size).to eq("5.0 MB")
    end

    it "rounds to 2 decimal places" do
      report = build(:supply_chain_report, file_size_bytes: 1_572_864)
      expect(report.formatted_size).to eq("1.5 MB")
    end
  end

  describe "#days_until_expiry" do
    it "returns nil when expires_at is nil" do
      report = build(:supply_chain_report, expires_at: nil)
      expect(report.days_until_expiry).to be_nil
    end

    it "returns positive days for future expiry" do
      report = build(:supply_chain_report, expires_at: 30.days.from_now)
      expect(report.days_until_expiry).to be_within(1).of(30)
    end

    it "returns negative days for past expiry" do
      report = build(:supply_chain_report, expires_at: 5.days.ago)
      expect(report.days_until_expiry).to be < 0
    end

    it "returns 0 for expiry today" do
      report = build(:supply_chain_report, expires_at: Date.current.end_of_day)
      expect(report.days_until_expiry).to eq(0)
    end
  end

  describe "generation workflow" do
    describe "#start_generation!" do
      it "updates status to generating" do
        report = create(:supply_chain_report, :pending, account: account)
        report.start_generation!
        expect(report.status).to eq("generating")
      end

      it "persists the change" do
        report = create(:supply_chain_report, :pending, account: account)
        report.start_generation!
        report.reload
        expect(report.status).to eq("generating")
      end
    end

    describe "#complete_generation!" do
      let(:report) { create(:supply_chain_report, :generating, account: account) }

      it "updates status to completed" do
        report.complete_generation!(
          file_path: "/tmp/report.pdf",
          file_url: "https://example.com/report.pdf",
          file_size: 1024,
          summary_data: { total: 100 }
        )
        expect(report.status).to eq("completed")
      end

      it "sets file_path" do
        report.complete_generation!(
          file_path: "/tmp/report.pdf",
          file_url: "https://example.com/report.pdf",
          file_size: 1024
        )
        expect(report.file_path).to eq("/tmp/report.pdf")
      end

      it "sets file_url" do
        report.complete_generation!(
          file_path: "/tmp/report.pdf",
          file_url: "https://example.com/report.pdf",
          file_size: 1024
        )
        expect(report.file_url).to eq("https://example.com/report.pdf")
      end

      it "sets file_size_bytes" do
        report.complete_generation!(
          file_path: "/tmp/report.pdf",
          file_size: 2048
        )
        expect(report.file_size_bytes).to eq(2048)
      end

      it "sets summary data" do
        summary = { total_components: 150, vulnerabilities: 5 }
        report.complete_generation!(
          file_path: "/tmp/report.pdf",
          summary_data: summary
        )
        expect(report.summary).to eq(summary.stringify_keys)
      end

      it "sets generated_at timestamp" do
        report.complete_generation!(file_path: "/tmp/report.pdf")
        expect(report.generated_at).to be_within(1.second).of(Time.current)
      end

      it "sets expires_at based on default_expiration" do
        report.complete_generation!(file_path: "/tmp/report.pdf")
        expect(report.expires_at).to be_present
      end

      it "persists all changes" do
        report.complete_generation!(
          file_path: "/tmp/report.pdf",
          file_url: "https://example.com/report.pdf",
          file_size: 1024
        )
        report.reload
        expect(report.status).to eq("completed")
        expect(report.file_path).to be_present
      end
    end

    describe "#fail_generation!" do
      let(:report) { create(:supply_chain_report, :generating, account: account) }

      it "updates status to failed" do
        report.fail_generation!("Something went wrong")
        expect(report.status).to eq("failed")
      end

      it "stores error message in metadata" do
        report.fail_generation!("File not found")
        expect(report.metadata["error"]).to eq("File not found")
      end

      it "preserves existing metadata" do
        report.update!(metadata: { "attempt" => 1 })
        report.fail_generation!("Failed again")
        expect(report.metadata["attempt"]).to eq(1)
        expect(report.metadata["error"]).to eq("Failed again")
      end

      it "persists the change" do
        report.fail_generation!("Test error")
        report.reload
        expect(report.status).to eq("failed")
      end
    end
  end

  describe "expiration methods" do
    describe "#expire!" do
      it "updates status to expired" do
        report = create(:supply_chain_report, :completed, account: account)
        report.expire!
        expect(report.status).to eq("expired")
      end

      it "persists the change" do
        report = create(:supply_chain_report, :completed, account: account)
        report.expire!
        report.reload
        expect(report.status).to eq("expired")
      end
    end

    describe "#extend_expiration!" do
      it "extends expiration by specified days" do
        original_expiry = 30.days.from_now
        report = create(:supply_chain_report, :completed, account: account, expires_at: original_expiry)
        report.extend_expiration!(7)
        expect(report.expires_at).to be_within(1.minute).of(original_expiry + 7.days)
      end

      it "sets expiration when nil" do
        report = create(:supply_chain_report, :completed, account: account, expires_at: nil)
        report.extend_expiration!(30)
        expect(report.expires_at).to be_within(1.minute).of(30.days.from_now)
      end

      it "persists the change" do
        report = create(:supply_chain_report, :completed, account: account, expires_at: 1.day.from_now)
        report.extend_expiration!(7)
        report.reload
        expect(report.expires_at).to be > 1.day.from_now
      end
    end
  end

  describe "#default_expiration" do
    it "returns 30 days for sbom_export" do
      report = build(:supply_chain_report, :sbom_export)
      expect(report.default_expiration).to be_within(1.minute).of(30.days.from_now)
    end

    it "returns 7 days for vulnerability_report" do
      report = build(:supply_chain_report, :vulnerability_report)
      expect(report.default_expiration).to be_within(1.minute).of(7.days.from_now)
    end

    it "returns 30 days for license_report" do
      report = build(:supply_chain_report, :license_report)
      expect(report.default_expiration).to be_within(1.minute).of(30.days.from_now)
    end

    it "returns 90 days for attribution" do
      report = build(:supply_chain_report, :attribution)
      expect(report.default_expiration).to be_within(1.minute).of(90.days.from_now)
    end

    it "returns 30 days for compliance_summary" do
      report = build(:supply_chain_report, :compliance_summary)
      expect(report.default_expiration).to be_within(1.minute).of(30.days.from_now)
    end

    it "returns 90 days for vendor_assessment" do
      report = build(:supply_chain_report, :vendor_assessment)
      expect(report.default_expiration).to be_within(1.minute).of(90.days.from_now)
    end

    it "returns 14 days for custom report type" do
      report = build(:supply_chain_report, report_type: "custom")
      expect(report.default_expiration).to be_within(1.minute).of(14.days.from_now)
    end
  end

  describe "#file_extension" do
    it "returns .pdf for pdf format" do
      report = build(:supply_chain_report, format: "pdf")
      expect(report.file_extension).to eq(".pdf")
    end

    it "returns .json for json format" do
      report = build(:supply_chain_report, format: "json")
      expect(report.file_extension).to eq(".json")
    end

    it "returns .csv for csv format" do
      report = build(:supply_chain_report, format: "csv")
      expect(report.file_extension).to eq(".csv")
    end

    it "returns .html for html format" do
      report = build(:supply_chain_report, format: "html")
      expect(report.file_extension).to eq(".html")
    end

    it "returns .xml for xml format" do
      report = build(:supply_chain_report, format: "xml")
      expect(report.file_extension).to eq(".xml")
    end

    it "returns .spdx.json for spdx format" do
      report = build(:supply_chain_report, format: "spdx")
      expect(report.file_extension).to eq(".spdx.json")
    end

    it "returns .cdx.json for cyclonedx format" do
      report = build(:supply_chain_report, format: "cyclonedx")
      expect(report.file_extension).to eq(".cdx.json")
    end

    it "returns .txt for unknown format" do
      report = build(:supply_chain_report)
      allow(report).to receive(:format).and_return("unknown")
      expect(report.file_extension).to eq(".txt")
    end
  end

  describe "#suggested_filename" do
    it "includes the report name" do
      report = build(:supply_chain_report, name: "Security Report", format: "pdf")
      expect(report.suggested_filename).to include("security_report")
    end

    it "includes the timestamp from generated_at" do
      report = build(:supply_chain_report,
                    name: "Test Report",
                    format: "pdf",
                    generated_at: Time.zone.parse("2024-01-15"))
      expect(report.suggested_filename).to include("20240115")
    end

    it "uses current date when generated_at is nil" do
      report = build(:supply_chain_report, name: "Test Report", format: "pdf", generated_at: nil)
      expect(report.suggested_filename).to include(Time.current.strftime("%Y%m%d"))
    end

    it "includes the file extension" do
      report = build(:supply_chain_report, name: "Test", format: "pdf")
      expect(report.suggested_filename).to end_with(".pdf")
    end

    it "sanitizes special characters" do
      report = build(:supply_chain_report, name: "Test @ Report #1", format: "json")
      expect(report.suggested_filename).to match(/test_report_1_\d+\.json/)
    end

    it "converts to lowercase" do
      report = build(:supply_chain_report, name: "UPPERCASE REPORT", format: "csv")
      expect(report.suggested_filename).to match(/^[a-z0-9_]+\.csv$/)
    end
  end

  describe "#summary_data" do
    let(:report) do
      create(:supply_chain_report, :completed, :with_sbom,
            account: account,
            name: "Test Report",
            description: "Test description",
            file_size_bytes: 2048)
    end

    it "includes basic report information" do
      summary = report.summary_data
      expect(summary[:id]).to eq(report.id)
      expect(summary[:name]).to eq("Test Report")
      expect(summary[:description]).to eq("Test description")
      expect(summary[:report_type]).to eq(report.report_type)
      expect(summary[:format]).to eq(report.format)
      expect(summary[:status]).to eq(report.status)
    end

    it "includes sbom_id when associated" do
      summary = report.summary_data
      expect(summary[:sbom_id]).to eq(report.sbom_id)
    end

    it "includes file information" do
      summary = report.summary_data
      expect(summary[:file_size_bytes]).to eq(2048)
      expect(summary[:formatted_size]).to eq(report.formatted_size)
    end

    it "includes timestamps" do
      summary = report.summary_data
      expect(summary[:generated_at]).to eq(report.generated_at)
      expect(summary[:expires_at]).to eq(report.expires_at)
      expect(summary[:created_at]).to eq(report.created_at)
    end

    it "includes computed fields" do
      summary = report.summary_data
      expect(summary[:days_until_expiry]).to eq(report.days_until_expiry)
      expect(summary[:downloadable]).to eq(report.downloadable?)
    end
  end

  describe "#detailed_report" do
    let(:report) do
      create(:supply_chain_report, :completed,
            account: account,
            parameters: { filter: "critical" },
            summary: { total: 100 },
            file_url: "https://example.com/report.pdf")
    end

    it "includes summary data" do
      details = report.detailed_report
      expect(details[:summary]).to be_present
      expect(details[:summary][:id]).to eq(report.id)
    end

    it "includes parameters" do
      details = report.detailed_report
      expect(details[:parameters]).to eq(report.parameters)
    end

    it "includes report summary" do
      details = report.detailed_report
      expect(details[:report_summary]).to eq(report.summary)
    end

    it "includes file_url" do
      details = report.detailed_report
      expect(details[:file_url]).to eq("https://example.com/report.pdf")
    end
  end

  describe "class methods" do
    describe ".generate_sbom_export" do
      it "creates a report with correct attributes" do
        report = described_class.generate_sbom_export(
          account: account,
          sbom: sbom,
          format: "cyclonedx",
          created_by: user
        )

        expect(report).to be_persisted
        expect(report.account).to eq(account)
        expect(report.sbom).to eq(sbom)
        expect(report.created_by).to eq(user)
        expect(report.report_type).to eq("sbom_export")
        expect(report.format).to eq("cyclonedx")
      end

      it "generates name from sbom name" do
        sbom.update!(name: "Test SBOM")
        report = described_class.generate_sbom_export(
          account: account,
          sbom: sbom
        )
        expect(report.name).to eq("SBOM Export - Test SBOM")
      end

      it "uses sbom_id when name is nil" do
        sbom.update!(name: nil)
        report = described_class.generate_sbom_export(
          account: account,
          sbom: sbom
        )
        expect(report.name).to include(sbom.sbom_id)
      end

      it "sets parameters with sbom_id and format" do
        report = described_class.generate_sbom_export(
          account: account,
          sbom: sbom,
          format: "spdx"
        )
        expect(report.parameters["sbom_id"]).to eq(sbom.id)
        expect(report.parameters["format"]).to eq("spdx")
      end

      it "defaults to pending status" do
        report = described_class.generate_sbom_export(
          account: account,
          sbom: sbom
        )
        expect(report.status).to eq("pending")
      end
    end

    describe ".generate_vulnerability_report" do
      it "creates a report with correct attributes" do
        report = described_class.generate_vulnerability_report(
          account: account,
          sbom: sbom,
          created_by: user,
          filters: { severity: "critical" }
        )

        expect(report).to be_persisted
        expect(report.account).to eq(account)
        expect(report.sbom).to eq(sbom)
        expect(report.created_by).to eq(user)
        expect(report.report_type).to eq("vulnerability_report")
        expect(report.format).to eq("pdf")
      end

      it "generates name with sbom name" do
        sbom.update!(name: "My App")
        report = described_class.generate_vulnerability_report(
          account: account,
          sbom: sbom
        )
        expect(report.name).to eq("Vulnerability Report - My App")
      end

      it "generates name without sbom" do
        report = described_class.generate_vulnerability_report(
          account: account,
          sbom: nil
        )
        expect(report.name).to eq("Vulnerability Report")
      end

      it "stores filters in parameters" do
        filters = { severity: "high", status: "open" }
        report = described_class.generate_vulnerability_report(
          account: account,
          filters: filters
        )
        expect(report.parameters["filters"]).to eq(filters.stringify_keys)
      end

      it "works without sbom" do
        report = described_class.generate_vulnerability_report(
          account: account,
          sbom: nil
        )
        expect(report.sbom).to be_nil
        expect(report.parameters["sbom_id"]).to be_nil
      end
    end

    describe ".generate_license_report" do
      it "creates a report with correct attributes" do
        report = described_class.generate_license_report(
          account: account,
          sbom: sbom,
          created_by: user
        )

        expect(report).to be_persisted
        expect(report.account).to eq(account)
        expect(report.sbom).to eq(sbom)
        expect(report.created_by).to eq(user)
        expect(report.report_type).to eq("license_report")
        expect(report.format).to eq("pdf")
      end

      it "generates name with sbom" do
        sbom.update!(name: "Test App")
        report = described_class.generate_license_report(
          account: account,
          sbom: sbom
        )
        expect(report.name).to eq("License Report - Test App")
      end

      it "generates name without sbom" do
        report = described_class.generate_license_report(
          account: account,
          sbom: nil
        )
        expect(report.name).to eq("License Report")
      end

      it "stores sbom_id in parameters" do
        report = described_class.generate_license_report(
          account: account,
          sbom: sbom
        )
        expect(report.parameters["sbom_id"]).to eq(sbom.id)
      end
    end

    describe ".generate_attribution" do
      it "creates a report with correct attributes" do
        report = described_class.generate_attribution(
          account: account,
          sbom: sbom,
          created_by: user
        )

        expect(report).to be_persisted
        expect(report.account).to eq(account)
        expect(report.sbom).to eq(sbom)
        expect(report.created_by).to eq(user)
        expect(report.report_type).to eq("attribution")
        expect(report.format).to eq("html")
      end

      it "generates name from sbom" do
        sbom.update!(name: "My Project")
        report = described_class.generate_attribution(
          account: account,
          sbom: sbom
        )
        expect(report.name).to eq("Attribution Notice - My Project")
      end

      it "uses sbom_id when name is nil" do
        sbom.update!(name: nil)
        report = described_class.generate_attribution(
          account: account,
          sbom: sbom
        )
        expect(report.name).to include(sbom.sbom_id)
      end

      it "stores sbom_id in parameters" do
        report = described_class.generate_attribution(
          account: account,
          sbom: sbom
        )
        expect(report.parameters["sbom_id"]).to eq(sbom.id)
      end
    end

    describe ".generate_compliance_summary" do
      it "creates a report with correct attributes" do
        report = described_class.generate_compliance_summary(
          account: account,
          compliance_type: "soc2",
          created_by: user
        )

        expect(report).to be_persisted
        expect(report.account).to eq(account)
        expect(report.created_by).to eq(user)
        expect(report.report_type).to eq("compliance_summary")
        expect(report.format).to eq("pdf")
      end

      it "generates name with compliance type" do
        report = described_class.generate_compliance_summary(
          account: account,
          compliance_type: "hipaa"
        )
        expect(report.name).to eq("Compliance Summary - HIPAA")
      end

      it "stores compliance_type in parameters" do
        report = described_class.generate_compliance_summary(
          account: account,
          compliance_type: "gdpr"
        )
        expect(report.parameters["compliance_type"]).to eq("gdpr")
      end

      it "does not require sbom" do
        report = described_class.generate_compliance_summary(
          account: account,
          compliance_type: "iso27001"
        )
        expect(report.sbom).to be_nil
      end
    end
  end

  describe "callbacks" do
    describe "sanitize_jsonb_fields" do
      it "initializes parameters as empty hash when nil" do
        report = create(:supply_chain_report, account: account, parameters: nil)
        expect(report.parameters).to eq({})
      end

      it "initializes summary as empty hash when nil" do
        report = create(:supply_chain_report, account: account, summary: nil)
        expect(report.summary).to eq({})
      end

      it "initializes metadata as empty hash when nil" do
        report = create(:supply_chain_report, account: account, metadata: nil)
        expect(report.metadata).to eq({})
      end

      it "preserves existing parameters" do
        params = { filter: "critical" }
        report = create(:supply_chain_report, account: account, parameters: params)
        expect(report.parameters).to eq(params.stringify_keys)
      end

      it "preserves existing summary" do
        summary = { total: 100 }
        report = create(:supply_chain_report, account: account, summary: summary)
        expect(report.summary).to eq(summary.stringify_keys)
      end

      it "preserves existing metadata" do
        metadata = { version: "1.0" }
        report = create(:supply_chain_report, account: account, metadata: metadata)
        expect(report.metadata).to eq(metadata.stringify_keys)
      end
    end
  end
end
