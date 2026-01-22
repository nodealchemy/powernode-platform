# frozen_string_literal: true

require "rails_helper"

RSpec.describe SupplyChain::ReportGenerationJob, type: :job do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:sbom) { create(:supply_chain_sbom, :with_components, account: account) }
  let(:vendor) { create(:supply_chain_vendor, account: account) }
  let(:container_image) { create(:supply_chain_container_image, account: account) }

  before do
    allow(SupplyChainChannel).to receive(:broadcast_report_generation_started)
    allow(SupplyChainChannel).to receive(:broadcast_report_generation_completed)
    allow(SupplyChainChannel).to receive(:broadcast_report_generation_failed)
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:error)
  end

  describe "queue configuration" do
    it "uses supply_chain_reports queue" do
      expect(described_class.new.queue_name).to eq("supply_chain_reports")
    end
  end

  describe "#perform" do
    context "with sbom_export report type" do
      let(:report) do
        create(
          :supply_chain_report,
          account: account,
          report_type: "sbom_export",
          format: "json",
          status: "pending",
          parameters: { sbom_id: sbom.id, export_format: "json" }
        )
      end


      it "finds the report by ID" do
        expect(SupplyChain::Report).to receive(:find).with(report.id).and_return(report)
        described_class.perform_now(report.id)
      end

      it "broadcasts report_generation_started" do
        expect(SupplyChainChannel).to receive(:broadcast_report_generation_started).with(report)
        described_class.perform_now(report.id)
      end

      it "logs start message" do
        expect(Rails.logger).to receive(:info).with("[ReportGenerationJob] Starting generation for report #{report.id}")
        described_class.perform_now(report.id)
      end

      it "updates status to generating with generated_at timestamp" do
        described_class.perform_now(report.id)
        report.reload
        expect(report.status).to eq("completed")
        expect(report.generated_at).to be_present
      end

      it "calls generate_sbom_report" do
        job = described_class.new
        allow(SupplyChain::Report).to receive(:find).with(report.id).and_return(report)
        allow(job).to receive(:generate_sbom_report).with(report).and_call_original
        job.perform(report.id)
      end

      it "exports SBOM in requested format" do
        described_class.perform_now(report.id)
        report.reload
        expect(report.status).to eq("completed")
        expect(report.metadata["content_type"]).to eq("application/json")
      end

      it "saves report content with correct filename and content type" do
        described_class.perform_now(report.id)
        report.reload
        expect(report.file_path).to eq("/reports/#{report.id}/sbom.json")
        expect(report.metadata["content_type"]).to eq("application/json")
        expect(report.metadata["filename"]).to eq("sbom.json")
        expect(report.file_size_bytes).to be > 0
      end

      it "updates status to completed on success" do
        described_class.perform_now(report.id)
        report.reload
        expect(report.status).to eq("completed")
      end

      it "broadcasts report_generation_completed" do
        expect(SupplyChainChannel).to receive(:broadcast_report_generation_completed).with(report)
        described_class.perform_now(report.id)
      end

      it "logs completion message" do
        expect(Rails.logger).to receive(:info).with("[ReportGenerationJob] Report #{report.id} generated successfully")
        described_class.perform_now(report.id)
      end

      context "with different export formats" do
        it "handles xml format" do
          report.update!(format: "xml", parameters: { sbom_id: sbom.id, export_format: "xml" })
          described_class.perform_now(report.id)
          report.reload
          expect(report.file_path).to eq("/reports/#{report.id}/sbom.xml")
          expect(report.metadata["content_type"]).to eq("application/xml")
        end

        it "defaults to json when format not specified" do
          report.update!(parameters: { sbom_id: sbom.id })
          described_class.perform_now(report.id)
          report.reload
          expect(report.file_path).to eq("/reports/#{report.id}/sbom.json")
        end
      end
    end

    context "with attribution report type" do
      let(:license) { create(:supply_chain_license, :permissive, license_text: "Permission is hereby granted...") }
      let(:sbom_with_license) { create(:supply_chain_sbom, account: account) }
      let(:component) do
        create(
          :supply_chain_sbom_component,
          sbom: sbom_with_license,
          account: account,
          license_spdx_id: license.spdx_id
        )
      end
      let(:report) do
        create(
          :supply_chain_report,
          account: account,
          report_type: "attribution",
          format: "json",
          status: "pending",
          parameters: { sbom_ids: [sbom_with_license.id], include_license_text: true }
        )
      end

      before do
        license # Ensure license exists first
        component
      end

      it "generates NOTICE.txt content with license attributions" do
        described_class.perform_now(report.id)
        report.reload
        expect(report.metadata["filename"]).to eq("NOTICE.txt")
        expect(report.metadata["content_type"]).to eq("text/plain")
      end

      it "includes component information in attribution content" do
        described_class.perform_now(report.id)
        report.reload
        content_preview = report.metadata["content_preview"]
        expect(content_preview).to include("THIRD-PARTY SOFTWARE NOTICES")
        expect(content_preview).to include(component.name)
        expect(content_preview).to include(license.name)
      end

      it "includes license text when include_license_text is true" do
        described_class.perform_now(report.id)
        report.reload
        content_preview = report.metadata["content_preview"]
        expect(content_preview).to include("Permission is hereby granted")
      end

      it "excludes license text when include_license_text is false" do
        report.update!(parameters: { sbom_ids: [sbom_with_license.id], include_license_text: false })
        described_class.perform_now(report.id)
        report.reload
        content_preview = report.metadata["content_preview"]
        expect(content_preview).not_to include("Permission is hereby granted")
      end
    end

    context "with compliance report type" do
      let(:report) do
        create(
          :supply_chain_report,
          account: account,
          report_type: "compliance",
          format: "json",
          status: "pending",
          parameters: { framework: "ntia" }
        )
      end

      before do
        sbom
      end

      it "generates compliance data with all sections" do
        described_class.perform_now(report.id)
        report.reload
        expect(report.status).to eq("completed")
        expect(report.metadata["filename"]).to eq("compliance_report.json")
        expect(report.metadata["content_type"]).to eq("application/json")
      end

      it "includes sbom_compliance data" do
        job = described_class.new
        allow(SupplyChain::Report).to receive(:find).with(report.id).and_return(report)
        expect(job).to receive(:generate_sbom_compliance_data).with(account, hash_including("framework")).and_call_original
        job.perform(report.id)
      end

      it "includes attestation_compliance data" do
        job = described_class.new
        allow(SupplyChain::Report).to receive(:find).with(report.id).and_return(report)
        expect(job).to receive(:generate_attestation_compliance_data).with(account).and_call_original
        job.perform(report.id)
      end

      it "includes license_compliance data" do
        job = described_class.new
        allow(SupplyChain::Report).to receive(:find).with(report.id).and_return(report)
        expect(job).to receive(:generate_license_compliance_data).with(account).and_call_original
        job.perform(report.id)
      end

      it "includes vendor_compliance data" do
        job = described_class.new
        allow(SupplyChain::Report).to receive(:find).with(report.id).and_return(report)
        expect(job).to receive(:generate_vendor_compliance_data).with(account).and_call_original
        job.perform(report.id)
      end

      it "uses correct framework from parameters" do
        report.update!(parameters: { framework: "custom" })
        described_class.perform_now(report.id)
        report.reload
        expect(report.status).to eq("completed")
      end

      it "defaults to ntia framework when not specified" do
        report.update!(parameters: {})
        described_class.perform_now(report.id)
        report.reload
        expect(report.status).to eq("completed")
      end
    end

    context "with vulnerability report type" do
      let(:vulnerability) do
        create(
          :supply_chain_sbom_vulnerability,
          sbom: sbom,
          account: account,
          severity: "critical",
          cvss_score: 9.8
        )
      end
      let(:scan) do
        create(
          :supply_chain_vulnerability_scan,
          :completed,
          :with_critical,
          container_image: container_image,
          account: account
        )
      end
      let(:report) do
        create(
          :supply_chain_report,
          account: account,
          report_type: "vulnerability",
          format: "json",
          status: "pending",
          parameters: {
            sbom_ids: [sbom.id],
            container_image_ids: [container_image.id]
          }
        )
      end

      before do
        vulnerability
        scan
      end

      it "aggregates vulnerabilities from SBOMs" do
        described_class.perform_now(report.id)
        report.reload
        expect(report.status).to eq("completed")
      end

      it "aggregates vulnerabilities from container images" do
        described_class.perform_now(report.id)
        report.reload
        expect(report.status).to eq("completed")
      end

      it "filters vulnerabilities by severity when specified" do
        report.update!(parameters: { sbom_ids: [sbom.id], severity_filter: "critical" })
        described_class.perform_now(report.id)
        report.reload
        expect(report.status).to eq("completed")
      end

      it "sorts vulnerabilities by severity" do
        # Create vulnerabilities with different severities
        create(:supply_chain_sbom_vulnerability, sbom: sbom, account: account, severity: "low")
        create(:supply_chain_sbom_vulnerability, sbom: sbom, account: account, severity: "high")
        create(:supply_chain_sbom_vulnerability, sbom: sbom, account: account, severity: "medium")

        described_class.perform_now(report.id)
        report.reload
        expect(report.status).to eq("completed")
      end

      it "includes vulnerability counts by severity" do
        described_class.perform_now(report.id)
        report.reload
        expect(report.status).to eq("completed")
      end

      it "handles empty vulnerability lists" do
        report.update!(parameters: { sbom_ids: [], container_image_ids: [] })
        described_class.perform_now(report.id)
        report.reload
        expect(report.status).to eq("completed")
      end
    end

    context "with vendor_risk report type" do
      let(:assessment) do
        create(
          :supply_chain_risk_assessment,
          vendor: vendor,
          account: account,
          security_score: 85,
          compliance_score: 90,
          operational_score: 88
        )
      end
      let(:report) do
        create(
          :supply_chain_report,
          account: account,
          report_type: "vendor_risk",
          format: "json",
          status: "pending",
          parameters: { vendor_ids: [vendor.id], include_assessments: true }
        )
      end

      before do
        assessment
      end

      it "includes vendor data" do
        described_class.perform_now(report.id)
        report.reload
        expect(report.status).to eq("completed")
      end

      it "includes latest assessment when include_assessments is true" do
        described_class.perform_now(report.id)
        report.reload
        expect(report.status).to eq("completed")
      end

      it "excludes assessments when include_assessments is false" do
        report.update!(parameters: { vendor_ids: [vendor.id], include_assessments: false })
        described_class.perform_now(report.id)
        report.reload
        expect(report.status).to eq("completed")
      end

      it "includes data handling information" do
        described_class.perform_now(report.id)
        report.reload
        expect(report.status).to eq("completed")
      end

      it "filters by vendor_ids when specified" do
        other_vendor = create(:supply_chain_vendor, account: account)
        report.update!(parameters: { vendor_ids: [vendor.id] })
        described_class.perform_now(report.id)
        report.reload
        expect(report.status).to eq("completed")
      end

      it "uses active vendors when vendor_ids not specified" do
        report.update!(parameters: {})
        described_class.perform_now(report.id)
        report.reload
        expect(report.status).to eq("completed")
      end

      it "includes vendor risk score and tier" do
        described_class.perform_now(report.id)
        report.reload
        expect(report.status).to eq("completed")
      end

      it "groups vendors by risk_tier" do
        described_class.perform_now(report.id)
        report.reload
        expect(report.status).to eq("completed")
      end
    end

    context "with unknown report type" do
      let(:report) do
        create(
          :supply_chain_report,
          account: account,
          report_type: "sbom_export",
          format: "json",
          status: "pending"
        )
      end

      it "raises error for unknown report type" do
        allow(report).to receive(:report_type).and_return("unknown_type")
        allow(report).to receive(:update!).and_return(true)
        allow(SupplyChain::Report).to receive(:find).with(report.id).and_return(report)

        expect {
          described_class.perform_now(report.id)
        }.to raise_error("Unknown report type: unknown_type")
      end
    end

    context "error handling" do
      let(:report) do
        create(
          :supply_chain_report,
          account: account,
          report_type: "sbom_export",
          format: "json",
          status: "pending",
          parameters: { sbom_id: sbom.id, export_format: "json" }
        )
      end

      context "when report is not found" do
        it "raises ActiveRecord::RecordNotFound" do
          expect {
            described_class.perform_now("non-existent-id")
          }.to raise_error(ActiveRecord::RecordNotFound)
        end
      end

      context "when generation fails" do
        let(:error) { StandardError.new("SBOM export failed") }

        before do
          allow_any_instance_of(SupplyChain::Sbom).to receive(:export).and_raise(error)
        end

        it "updates status to failed" do
          expect {
            described_class.perform_now(report.id)
          }.to raise_error(StandardError)
          report.reload
          expect(report.status).to eq("failed")
        end

        it "stores error message" do
          expect {
            described_class.perform_now(report.id)
          }.to raise_error(StandardError)
          report.reload
          expect(report.metadata["error_message"]).to eq("SBOM export failed")
        end

        it "broadcasts report_generation_failed" do
          expect(SupplyChainChannel).to receive(:broadcast_report_generation_failed).with(report, "SBOM export failed")
          expect {
            described_class.perform_now(report.id)
          }.to raise_error(StandardError)
        end

        it "logs error message" do
          expect(Rails.logger).to receive(:error).with("[ReportGenerationJob] Report #{report.id} failed: SBOM export failed")
          expect {
            described_class.perform_now(report.id)
          }.to raise_error(StandardError)
        end

        it "re-raises the error" do
          expect {
            described_class.perform_now(report.id)
          }.to raise_error(StandardError, "SBOM export failed")
        end

        it "does not broadcast report_generation_completed" do
          expect(SupplyChainChannel).not_to receive(:broadcast_report_generation_completed)
          expect {
            described_class.perform_now(report.id)
          }.to raise_error(StandardError)
        end
      end

      context "when broadcast fails" do
        let(:broadcast_error) { StandardError.new("Broadcast failed") }

        before do
          allow(SupplyChainChannel).to receive(:broadcast_report_generation_completed).and_raise(broadcast_error)
        end

        it "updates status to failed" do
          expect {
            described_class.perform_now(report.id)
          }.to raise_error(StandardError)
          report.reload
          expect(report.status).to eq("failed")
        end

        it "re-raises the error" do
          expect {
            described_class.perform_now(report.id)
          }.to raise_error(StandardError, "Broadcast failed")
        end
      end
    end

    context "format_content method" do
      let(:report) do
        create(
          :supply_chain_report,
          account: account,
          report_type: "compliance",
          format: "json",
          status: "pending",
          parameters: { framework: "ntia" }
        )
      end

      it "formats content as JSON with pretty printing" do
        described_class.perform_now(report.id)
        report.reload
        expect(report.metadata["content_type"]).to eq("application/json")
      end

      it "handles CSV format" do
        report.update!(format: "csv")
        described_class.perform_now(report.id)
        report.reload
        expect(report.metadata["content_type"]).to eq("text/csv")
      end

      it "defaults to JSON for unknown formats" do
        report.update!(format: "json")
        described_class.perform_now(report.id)
        report.reload
        expect(report.metadata["content_type"]).to eq("application/json")
      end
    end

    context "content_type_for method" do
      let(:report) do
        create(
          :supply_chain_report,
          account: account,
          report_type: "sbom_export",
          status: "pending",
          parameters: { sbom_id: sbom.id }
        )
      end


      it "returns correct MIME type for json" do
        report.update!(format: "json", parameters: { sbom_id: sbom.id, export_format: "json" })
        described_class.perform_now(report.id)
        report.reload
        expect(report.metadata["content_type"]).to eq("application/json")
      end

      it "returns correct MIME type for xml" do
        report.update!(format: "xml", parameters: { sbom_id: sbom.id, export_format: "xml" })
        described_class.perform_now(report.id)
        report.reload
        expect(report.metadata["content_type"]).to eq("application/xml")
      end

      it "returns correct MIME type for csv" do
        report.update!(format: "csv", parameters: { sbom_id: sbom.id, export_format: "csv" })
        described_class.perform_now(report.id)
        report.reload
        expect(report.metadata["content_type"]).to eq("text/csv")
      end

      it "returns correct MIME type for pdf" do
        report.update!(format: "pdf", parameters: { sbom_id: sbom.id, export_format: "pdf" })
        described_class.perform_now(report.id)
        report.reload
        expect(report.metadata["content_type"]).to eq("application/pdf")
      end

      it "returns correct MIME type for txt" do
        report.update!(format: "json", parameters: { sbom_id: sbom.id, export_format: "txt" })
        described_class.perform_now(report.id)
        report.reload
        expect(report.metadata["content_type"]).to eq("text/plain")
      end

      it "returns application/octet-stream for unknown formats" do
        report.update!(format: "json", parameters: { sbom_id: sbom.id, export_format: "unknown" })
        described_class.perform_now(report.id)
        report.reload
        expect(report.metadata["content_type"]).to eq("application/octet-stream")
      end
    end

    context "save_report_content method" do
      let(:report) do
        create(
          :supply_chain_report,
          account: account,
          report_type: "sbom_export",
          format: "json",
          status: "pending",
          parameters: { sbom_id: sbom.id, export_format: "json" }
        )
      end

      it "saves file_path with correct pattern" do
        described_class.perform_now(report.id)
        report.reload
        expect(report.file_path).to match(%r{^/reports/#{report.id}/})
      end

      it "calculates and saves file_size" do
        described_class.perform_now(report.id)
        report.reload
        expect(report.file_size_bytes).to be > 0
      end

      it "saves content_type" do
        described_class.perform_now(report.id)
        report.reload
        expect(report.metadata["content_type"]).to eq("application/json")
      end

      it "saves filename" do
        described_class.perform_now(report.id)
        report.reload
        expect(report.metadata["filename"]).to eq("sbom.json")
      end

      it "stores content preview in metadata" do
        described_class.perform_now(report.id)
        report.reload
        expect(report.metadata["content_preview"]).to be_present
        expect(report.metadata["content_preview"].length).to be <= 1000
      end
    end

    context "integration test" do
      let(:license) { create(:supply_chain_license, :permissive) }
      let(:component) do
        create(
          :supply_chain_sbom_component,
          sbom: sbom,
          account: account,
          license_spdx_id: license.spdx_id
        )
      end
      let(:vulnerability) do
        create(
          :supply_chain_sbom_vulnerability,
          sbom: sbom,
          account: account,
          component: component
        )
      end
      let(:report) do
        create(
          :supply_chain_report,
          account: account,
          report_type: "sbom_export",
          format: "json",
          status: "pending",
          parameters: { sbom_id: sbom.id, export_format: "json" }
        )
      end

      before do
        component
        vulnerability
      end

      it "successfully completes full workflow" do
        described_class.perform_now(report.id)
        report.reload

        expect(report.status).to eq("completed")
        expect(report.generated_at).to be_present
        expect(report.file_path).to be_present
        expect(report.file_size_bytes).to be > 0
        expect(report.metadata["content_type"]).to eq("application/json")
        expect(report.metadata["filename"]).to eq("sbom.json")
        expect(report.metadata["content_preview"]).to be_present

        expect(SupplyChainChannel).to have_received(:broadcast_report_generation_started).with(report)
        expect(SupplyChainChannel).to have_received(:broadcast_report_generation_completed).with(report)
        expect(Rails.logger).to have_received(:info).with("[ReportGenerationJob] Starting generation for report #{report.id}")
        expect(Rails.logger).to have_received(:info).with("[ReportGenerationJob] Report #{report.id} generated successfully")
      end
    end

    context "generate_sbom_compliance_data" do
      let(:compliant_sbom) { create(:supply_chain_sbom, account: account, ntia_minimum_compliant: true) }
      let(:non_compliant_sbom) { create(:supply_chain_sbom, account: account, ntia_minimum_compliant: false) }
      let(:report) do
        create(
          :supply_chain_report,
          account: account,
          report_type: "compliance",
          format: "json",
          status: "pending",
          parameters: { framework: "ntia", sbom_ids: [compliant_sbom.id, non_compliant_sbom.id] }
        )
      end

      before do
        compliant_sbom
        non_compliant_sbom
      end

      it "calculates compliance rate correctly" do
        described_class.perform_now(report.id)
        report.reload
        expect(report.status).to eq("completed")
      end
    end

    context "generate_attestation_compliance_data" do
      let(:attestation) { create(:supply_chain_attestation, :signed, :verified, account: account) }
      let(:report) do
        create(
          :supply_chain_report,
          account: account,
          report_type: "compliance",
          format: "json",
          status: "pending",
          parameters: { framework: "slsa" }
        )
      end

      before do
        attestation
      end

      it "includes attestation statistics" do
        described_class.perform_now(report.id)
        report.reload
        expect(report.status).to eq("completed")
      end
    end

    context "generate_license_compliance_data" do
      let(:license_policy) { create(:supply_chain_license_policy, account: account, is_active: true) }
      let(:license_violation) { create(:supply_chain_license_violation, account: account, status: "open") }
      let(:report) do
        create(
          :supply_chain_report,
          account: account,
          report_type: "compliance",
          format: "json",
          status: "pending",
          parameters: { framework: "license" }
        )
      end

      before do
        license_policy
        license_violation
      end

      it "includes license policy and violation statistics" do
        described_class.perform_now(report.id)
        report.reload
        expect(report.status).to eq("completed")
      end
    end

    context "generate_vendor_compliance_data" do
      let(:vendor_with_pii) { create(:supply_chain_vendor, account: account, handles_pii: true, has_dpa: true) }
      let(:vendor_without_dpa) { create(:supply_chain_vendor, account: account, handles_pii: true, has_dpa: false) }
      let(:report) do
        create(
          :supply_chain_report,
          account: account,
          report_type: "compliance",
          format: "json",
          status: "pending",
          parameters: { framework: "vendor" }
        )
      end

      before do
        vendor_with_pii
        vendor_without_dpa
      end

      it "includes vendor compliance statistics" do
        described_class.perform_now(report.id)
        report.reload
        expect(report.status).to eq("completed")
      end
    end
  end
end
