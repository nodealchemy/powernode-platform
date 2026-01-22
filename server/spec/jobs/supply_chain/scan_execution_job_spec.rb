# frozen_string_literal: true

require "rails_helper"

RSpec.describe SupplyChain::ScanExecutionJob, type: :job do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:template) { create(:supply_chain_scan_template, :security, account: nil) }
  let(:instance) { create(:supply_chain_scan_instance, account: account, scan_template: template, configuration: {}) }
  let(:sbom) { create(:supply_chain_sbom, account: account) }
  let(:execution) do
    create(:supply_chain_scan_execution,
      account: account,
      scan_instance: instance,
      status: "pending",
      input_data: {
        "target_type" => "SupplyChain::Sbom",
        "target_id" => sbom.id
      }
    )
  end

  before do
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:error)
    allow(SupplyChainChannel).to receive(:broadcast_execution_started)
    allow(SupplyChainChannel).to receive(:broadcast_execution_completed)
    allow(SupplyChainChannel).to receive(:broadcast_execution_failed)
  end

  describe "queue configuration" do
    it "uses supply_chain_scans queue" do
      expect(described_class.new.queue_name).to eq("supply_chain_scans")
    end
  end

  describe "#perform" do
    context "with valid execution" do
      let(:vulnerability_service) { instance_double(SupplyChain::VulnerabilityCorrelationService) }
      let(:vulnerability_results) { { total_vulnerabilities: 10, critical: 2, high: 3 } }

      before do
        allow(SupplyChain::VulnerabilityCorrelationService).to receive(:new).and_return(vulnerability_service)
        allow(vulnerability_service).to receive(:correlate!).and_return(vulnerability_results)
      end

      it "finds execution by ID" do
        expect(SupplyChain::ScanExecution).to receive(:find).with(execution.id).and_return(execution)
        described_class.perform_now(execution.id)
      end

      it "broadcasts execution_started with execution" do
        expect(SupplyChainChannel).to receive(:broadcast_execution_started).with(execution)
        described_class.perform_now(execution.id)
      end

      it "updates status to running with started_at timestamp" do
        freeze_time do
          described_class.perform_now(execution.id)
          execution.reload
          # Status will be completed after job finishes
          expect(execution.started_at).to be_within(1.second).of(Time.current)
        end
      end

      it "updates execution with completed status, duration, and findings" do
        freeze_time do
          described_class.perform_now(execution.id)
          execution.reload

          expect(execution.status).to eq("completed")
          expect(execution.completed_at).to be_present
          expect(execution.duration_ms).to be_a(Integer)
          expect(execution.output_data["findings_count"]).to eq(10)
        end
      end

      it "broadcasts execution_completed with execution" do
        expect(SupplyChainChannel).to receive(:broadcast_execution_completed).with(execution)
        described_class.perform_now(execution.id)
      end

      it "logs start message with execution ID" do
        expect(Rails.logger).to receive(:info).with("[ScanExecutionJob] Starting execution #{execution.id}")
        described_class.perform_now(execution.id)
      end

      it "logs completion message with findings count" do
        expect(Rails.logger).to receive(:info).with("[ScanExecutionJob] Execution #{execution.id} completed with 10 findings")
        described_class.perform_now(execution.id)
      end
    end

    context "template category routing" do
      let(:vulnerability_service) { instance_double(SupplyChain::VulnerabilityCorrelationService) }
      let(:container_service) { instance_double(SupplyChain::ContainerScanService) }

      context "with security template" do
        let(:template) { create(:supply_chain_scan_template, :security) }
        let(:vulnerability_results) { { total_vulnerabilities: 5, critical: 2, high: 3 } }

        before do
          allow(SupplyChain::VulnerabilityCorrelationService).to receive(:new).and_return(vulnerability_service)
          allow(vulnerability_service).to receive(:correlate!).and_return(vulnerability_results)
        end

        it "calls execute_security_scan" do
          expect_any_instance_of(described_class).to receive(:execute_security_scan).and_call_original
          described_class.perform_now(execution.id)
        end

        it "returns vulnerability data in output_data" do
          described_class.perform_now(execution.id)
          execution.reload
          expect(execution.output_data["findings_count"]).to eq(5)
          expect(execution.output_data["total_vulnerabilities"]).to eq(5)
        end
      end

      context "with compliance template" do
        let(:template) { create(:supply_chain_scan_template, :compliance) }
        let(:vulnerability_results) { { total_vulnerabilities: 8, critical: 1, high: 2 } }

        before do
          allow(SupplyChain::VulnerabilityCorrelationService).to receive(:new).and_return(vulnerability_service)
          allow(vulnerability_service).to receive(:correlate!).and_return(vulnerability_results)
        end

        it "calls execute_compliance_scan" do
          expect_any_instance_of(described_class).to receive(:execute_compliance_scan).and_call_original
          described_class.perform_now(execution.id)
        end

        it "returns compliance data in output_data" do
          described_class.perform_now(execution.id)
          execution.reload
          expect(execution.output_data["findings_count"]).to eq(8)
        end
      end

      context "with license template" do
        let(:template) { create(:supply_chain_scan_template, :license) }
        let(:policy) { create(:supply_chain_license_policy, account: account, is_active: true) }
        let(:sbom_with_components) { create(:supply_chain_sbom, :with_components, account: account) }

        before do
          execution.update!(input_data: { "target_type" => "SupplyChain::Sbom", "target_id" => sbom_with_components.id })
          allow_any_instance_of(SupplyChain::LicensePolicy).to receive(:check_license).and_return(nil)
        end

        it "calls execute_license_scan" do
          expect_any_instance_of(described_class).to receive(:execute_license_scan).and_call_original
          described_class.perform_now(execution.id)
        end
      end

      context "with quality template" do
        let(:template) { create(:supply_chain_scan_template, :quality) }
        let(:container_image) { create(:supply_chain_container_image, account: account) }

        before do
          execution.update!(input_data: { "target_type" => "SupplyChain::ContainerImage", "target_id" => container_image.id })
          allow(SupplyChain::ContainerScanService).to receive(:new).and_return(container_service)
          allow(container_service).to receive(:scan!).and_return({ vulnerabilities: [{ id: "CVE-1", severity: "high" }] })
        end

        it "calls execute_quality_scan" do
          expect_any_instance_of(described_class).to receive(:execute_quality_scan).and_call_original
          described_class.perform_now(execution.id)
        end

        it "returns container scan data in output_data" do
          described_class.perform_now(execution.id)
          execution.reload
          expect(execution.output_data["findings_count"]).to eq(1)
          expect(execution.output_data["vulnerabilities"]).to be_present
        end
      end

      context "with custom template" do
        let(:template) { create(:supply_chain_scan_template, :custom) }

        it "calls execute_custom_scan" do
          expect_any_instance_of(described_class).to receive(:execute_custom_scan).and_call_original
          described_class.perform_now(execution.id)
        end

        it "returns custom scan data in output_data" do
          described_class.perform_now(execution.id)
          execution.reload
          expect(execution.output_data["message"]).to eq("Custom scan completed")
        end
      end
    end

    context "auto-remediation" do
      let(:vulnerability_service) { instance_double(SupplyChain::VulnerabilityCorrelationService) }
      let(:vulnerability_results) { { total_vulnerabilities: 10, critical: 2, high: 3 } }

      before do
        allow(SupplyChain::VulnerabilityCorrelationService).to receive(:new).and_return(vulnerability_service)
        allow(vulnerability_service).to receive(:correlate!).and_return(vulnerability_results)
      end

      context "when auto_remediate is true in config and findings exist" do
        before do
          instance.update!(configuration: { "auto_remediate" => true })
        end

        it "triggers auto-remediation" do
          expect {
            described_class.perform_now(execution.id)
          }.to change { SupplyChain::RemediationPlan.count }.by(1)
        end

        it "creates remediation plan with correct attributes" do
          described_class.perform_now(execution.id)
          plan = SupplyChain::RemediationPlan.last
          expect(plan.account).to eq(account)
          expect(plan.sbom).to eq(sbom)
          expect(plan.plan_type).to eq("auto_fix")
          expect(plan.status).to eq("draft")
          expect(plan.metadata["scan_execution_id"]).to eq(execution.id)
        end

        context "with remediation threshold" do
          before do
            execution.update!(input_data: execution.input_data.merge("remediation_threshold" => 15))
          end

          it "does not create plan when findings below threshold" do
            expect {
              described_class.perform_now(execution.id)
            }.not_to change { SupplyChain::RemediationPlan.count }
          end
        end
      end

      context "when auto_remediate is false" do
        before do
          instance.update!(configuration: { "auto_remediate" => false })
        end

        it "does not trigger auto-remediation" do
          expect {
            described_class.perform_now(execution.id)
          }.not_to change { SupplyChain::RemediationPlan.count }
        end
      end

      context "when findings_count is zero" do
        let(:vulnerability_results) { { total_vulnerabilities: 0 } }

        before do
          instance.update!(configuration: { "auto_remediate" => true })
        end

        it "does not trigger auto-remediation" do
          expect {
            described_class.perform_now(execution.id)
          }.not_to change { SupplyChain::RemediationPlan.count }
        end
      end
    end

    context "error handling" do
      context "when execution is not found" do
        it "raises ActiveRecord::RecordNotFound" do
          expect {
            described_class.perform_now("non-existent-id")
          }.to raise_error(ActiveRecord::RecordNotFound)
        end
      end

      context "when scan execution fails" do
        let(:error_message) { "Vulnerability scan failed" }

        before do
          allow(SupplyChain::VulnerabilityCorrelationService).to receive(:new).and_raise(StandardError.new(error_message))
        end

        it "updates status to failed with error_message" do
          freeze_time do
            expect {
              described_class.perform_now(execution.id)
            }.to raise_error(StandardError)

            execution.reload
            expect(execution.status).to eq("failed")
            expect(execution.error_message).to eq(error_message)
            expect(execution.completed_at).to be_within(1.second).of(Time.current)
          end
        end

        it "calculates duration even on failure" do
          freeze_time do
            expect {
              described_class.perform_now(execution.id)
            }.to raise_error(StandardError)

            execution.reload
            # Duration is calculated from started_at to completed_at in same frozen time
            expect(execution.duration_ms).to be_a(Integer)
          end
        end

        it "broadcasts execution_failed with error message" do
          expect(SupplyChainChannel).to receive(:broadcast_execution_failed).with(execution, error_message)
          expect {
            described_class.perform_now(execution.id)
          }.to raise_error(StandardError)
        end

        it "re-raises the error" do
          expect {
            described_class.perform_now(execution.id)
          }.to raise_error(StandardError, error_message)
        end

        it "logs error message" do
          expect(Rails.logger).to receive(:error).with("[ScanExecutionJob] Execution #{execution.id} failed: #{error_message}")
          expect {
            described_class.perform_now(execution.id)
          }.to raise_error(StandardError)
        end

        it "does not broadcast execution_completed" do
          expect(SupplyChainChannel).not_to receive(:broadcast_execution_completed)
          expect {
            described_class.perform_now(execution.id)
          }.to raise_error(StandardError)
        end
      end

      context "when execution fails before started_at is set" do
        it "handles failure gracefully even without started_at" do
          # This test verifies the job handles the edge case of started_at being nil
          # The actual implementation sets started_at before scan_instance is accessed,
          # so this edge case is difficult to trigger in practice
          execution_record = create(:supply_chain_scan_execution,
            account: account,
            scan_instance: instance,
            status: "pending",
            started_at: nil
          )

          # Simulate a failure during the update by making the job fail early
          allow(SupplyChain::ScanExecution).to receive(:find).and_call_original
          allow_any_instance_of(SupplyChain::ScanExecution).to receive(:update!)
            .and_wrap_original do |original, *args|
              original.call(*args)
              if args.first[:status] == "running"
                raise StandardError.new("Early failure during update")
              end
            end

          expect {
            described_class.perform_now(execution_record.id)
          }.to raise_error(StandardError)

          # The execution should have been marked as failed with some duration
          execution_record.reload
          expect(execution_record.status).to eq("failed")
        end
      end
    end
  end

  describe "#execute_security_scan" do
    let(:vulnerability_service) { instance_double(SupplyChain::VulnerabilityCorrelationService) }
    let(:vulnerability_results) { { total_vulnerabilities: 25, critical: 5, high: 10 } }

    before do
      allow(SupplyChain::VulnerabilityCorrelationService).to receive(:new).and_return(vulnerability_service)
      allow(vulnerability_service).to receive(:correlate!).and_return(vulnerability_results)
    end

    it "calls VulnerabilityCorrelationService with sbom" do
      expect(SupplyChain::VulnerabilityCorrelationService).to receive(:new).with(sbom: sbom).and_return(vulnerability_service)
      described_class.perform_now(execution.id)
    end

    it "returns total_vulnerabilities as findings_count" do
      described_class.perform_now(execution.id)
      execution.reload
      expect(execution.output_data["findings_count"]).to eq(25)
    end

    it "returns full vulnerability results" do
      described_class.perform_now(execution.id)
      execution.reload
      expect(execution.output_data["total_vulnerabilities"]).to eq(25)
      expect(execution.output_data["critical"]).to eq(5)
      expect(execution.output_data["high"]).to eq(10)
    end

    context "when target is not found" do
      before do
        execution.update!(input_data: { "target_type" => "SupplyChain::Sbom", "target_id" => "non-existent-id" })
      end

      it "returns empty results" do
        described_class.perform_now(execution.id)
        execution.reload
        expect(execution.output_data["findings_count"]).to eq(0)
      end
    end

    context "with ContainerImage target" do
      let(:container_image) { create(:supply_chain_container_image, account: account) }
      let(:container_service) { instance_double(SupplyChain::ContainerScanService) }
      let(:scan_results) { { vulnerabilities: [{ id: "CVE-1", severity: "critical" }, { id: "CVE-2", severity: "high" }] } }

      before do
        execution.update!(input_data: { "target_type" => "SupplyChain::ContainerImage", "target_id" => container_image.id })
        allow(SupplyChain::ContainerScanService).to receive(:new).and_return(container_service)
        allow(container_service).to receive(:scan!).and_return(scan_results)
      end

      it "calls ContainerScanService with image" do
        expect(SupplyChain::ContainerScanService).to receive(:new).with(account: account, image: container_image).and_return(container_service)
        described_class.perform_now(execution.id)
      end

      it "returns vulnerabilities count as findings_count" do
        described_class.perform_now(execution.id)
        execution.reload
        expect(execution.output_data["findings_count"]).to eq(2)
      end
    end

    context "with Repository target (for SBOM generation)" do
      let(:provider) { create(:devops_provider, account: account) }
      let(:repository) { create(:devops_repository, account: account, provider: provider) }
      let(:sbom_service) { instance_double(SupplyChain::SbomGenerationService) }
      let(:generated_sbom) do
        # Create document with 15 components so update_counters callback calculates correct count
        components = Array.new(15) { |i| { "name" => "component-#{i}", "version" => "1.0.0" } }
        document = { "bomFormat" => "CycloneDX", "specVersion" => "1.5", "components" => components }
        create(:supply_chain_sbom, account: account, document: document, vulnerability_count: 3)
      end

      before do
        execution.update!(input_data: { "target_type" => "Repository", "target_id" => repository.id })
      end

      it "calls SbomGenerationService with repository" do
        allow(SupplyChain::SbomGenerationService).to receive(:new).and_return(sbom_service)
        allow(sbom_service).to receive(:generate).and_return(generated_sbom)
        expect(SupplyChain::SbomGenerationService).to receive(:new).with(
          account: account,
          repository: repository
        ).and_return(sbom_service)
        expect(sbom_service).to receive(:generate).with(
          source_path: ".",
          format: "cyclonedx_1_5"
        ).and_return(generated_sbom)
        described_class.perform_now(execution.id)
      end

      it "returns component_count as findings_count" do
        allow(SupplyChain::SbomGenerationService).to receive(:new).and_return(sbom_service)
        allow(sbom_service).to receive(:generate).and_return(generated_sbom)
        described_class.perform_now(execution.id)
        execution.reload
        expect(execution.output_data["findings_count"]).to eq(15)
        expect(execution.output_data["sbom_id"]).to eq(generated_sbom.id)
      end
    end
  end

  describe "#execute_license_scan" do
    let(:template) { create(:supply_chain_scan_template, :license) }
    let(:policy) { create(:supply_chain_license_policy, account: account, is_active: true) }
    let(:license) { create(:supply_chain_license, :copyleft, spdx_id: "GPL-3.0") }
    let(:sbom_with_licenses) { create(:supply_chain_sbom, account: account) }
    let(:component) { create(:supply_chain_sbom_component, sbom: sbom_with_licenses, account: account, license_spdx_id: license.spdx_id) }

    before do
      execution.update!(input_data: { "target_type" => "SupplyChain::Sbom", "target_id" => sbom_with_licenses.id })
      license # Ensure license exists before component
      component # Create component
    end

    context "with active license policy" do
      let(:violation) { { component_id: component.id, license_id: license.id, reason: "Copyleft detected" } }

      before do
        policy # Ensure policy exists before job runs
        allow_any_instance_of(SupplyChain::LicensePolicy).to receive(:check_license).and_return(violation)
      end

      it "uses policy from config if specified" do
        execution.update!(input_data: execution.input_data.merge("policy_id" => policy.id))
        described_class.perform_now(execution.id)
        execution.reload
        expect(execution.output_data["policy_id"]).to eq(policy.id)
      end

      it "uses first active policy if no policy_id in config" do
        described_class.perform_now(execution.id)
        execution.reload
        expect(execution.output_data["policy_id"]).to eq(policy.id)
      end

      it "returns violations count as findings_count" do
        described_class.perform_now(execution.id)
        execution.reload
        expect(execution.output_data["findings_count"]).to eq(1)
      end

      it "returns violations in output_data" do
        described_class.perform_now(execution.id)
        execution.reload
        expect(execution.output_data["violations"].length).to eq(1)
        expect(execution.output_data["violations"].first["reason"]).to eq("Copyleft detected")
      end
    end

    context "when no active policy exists" do
      before do
        policy.update!(is_active: false)
      end

      it "returns empty results" do
        described_class.perform_now(execution.id)
        execution.reload
        expect(execution.output_data["findings_count"]).to eq(0)
      end
    end

    context "when target is not found" do
      before do
        execution.update!(input_data: { "target_type" => "SupplyChain::Sbom", "target_id" => "non-existent-id" })
      end

      it "returns empty results" do
        described_class.perform_now(execution.id)
        execution.reload
        expect(execution.output_data["findings_count"]).to eq(0)
      end
    end
  end

  describe "#execute_quality_scan" do
    let(:template) { create(:supply_chain_scan_template, :quality) }
    let(:container_image) { create(:supply_chain_container_image, account: account) }
    let(:container_service) { instance_double(SupplyChain::ContainerScanService) }
    let(:scan_results) do
      {
        vulnerabilities: [
          { id: "CVE-1", severity: "critical" },
          { id: "CVE-2", severity: "high" }
        ],
        sbom: { components: [] }
      }
    end

    before do
      execution.update!(input_data: { "target_type" => "SupplyChain::ContainerImage", "target_id" => container_image.id })
      allow(SupplyChain::ContainerScanService).to receive(:new).and_return(container_service)
      allow(container_service).to receive(:scan!).and_return(scan_results)
    end

    it "calls ContainerScanService with image" do
      expect(SupplyChain::ContainerScanService).to receive(:new).with(account: account, image: container_image).and_return(container_service)
      described_class.perform_now(execution.id)
    end

    it "returns vulnerabilities count as findings_count" do
      described_class.perform_now(execution.id)
      execution.reload
      expect(execution.output_data["findings_count"]).to eq(2)
    end

    it "returns full scan results" do
      described_class.perform_now(execution.id)
      execution.reload
      expect(execution.output_data["vulnerabilities"].length).to eq(2)
      expect(execution.output_data["sbom"]).to be_present
    end

    context "when target is not a ContainerImage" do
      before do
        execution.update!(input_data: { "target_type" => "SupplyChain::Sbom", "target_id" => sbom.id })
      end

      it "returns empty results" do
        described_class.perform_now(execution.id)
        execution.reload
        expect(execution.output_data["findings_count"]).to eq(0)
      end
    end

    context "when scan returns no vulnerabilities" do
      let(:scan_results) { { vulnerabilities: [] } }

      it "returns zero findings_count" do
        described_class.perform_now(execution.id)
        execution.reload
        expect(execution.output_data["findings_count"]).to eq(0)
      end
    end
  end

  describe "#execute_custom_scan" do
    let(:template) { create(:supply_chain_scan_template, :custom, default_configuration: { pattern: "test" }) }

    it "evaluates template default_configuration" do
      described_class.perform_now(execution.id)
      execution.reload
      expect(execution.output_data["message"]).to eq("Custom scan completed")
    end

    it "returns rules count in output_data" do
      described_class.perform_now(execution.id)
      execution.reload
      expect(execution.output_data["rules_evaluated"]).to eq(1)
    end

    it "returns zero findings_count" do
      described_class.perform_now(execution.id)
      execution.reload
      expect(execution.output_data["findings_count"]).to eq(0)
    end

    context "when template has no default_configuration" do
      let(:template) { create(:supply_chain_scan_template, :custom, default_configuration: nil) }

      it "returns zero rules_evaluated" do
        described_class.perform_now(execution.id)
        execution.reload
        expect(execution.output_data["rules_evaluated"]).to eq(0)
      end
    end
  end

  describe "#resolve_target" do
    context "with Sbom target" do
      let(:vulnerability_service) { instance_double(SupplyChain::VulnerabilityCorrelationService) }

      before do
        allow(SupplyChain::VulnerabilityCorrelationService).to receive(:new).and_return(vulnerability_service)
        allow(vulnerability_service).to receive(:correlate!).and_return({ total_vulnerabilities: 0 })
      end

      it "returns sbom from account scope" do
        expect(SupplyChain::VulnerabilityCorrelationService).to receive(:new).with(sbom: sbom).and_return(vulnerability_service)
        described_class.perform_now(execution.id)
      end

      it "handles 'Sbom' string type" do
        execution.update!(input_data: { "target_type" => "Sbom", "target_id" => sbom.id })
        expect(SupplyChain::VulnerabilityCorrelationService).to receive(:new).with(sbom: sbom).and_return(vulnerability_service)
        described_class.perform_now(execution.id)
      end

      it "handles 'SupplyChain::Sbom' string type" do
        execution.update!(input_data: { "target_type" => "SupplyChain::Sbom", "target_id" => sbom.id })
        expect(SupplyChain::VulnerabilityCorrelationService).to receive(:new).with(sbom: sbom).and_return(vulnerability_service)
        described_class.perform_now(execution.id)
      end
    end

    context "with ContainerImage target" do
      let(:container_image) { create(:supply_chain_container_image, account: account) }
      let(:container_service) { instance_double(SupplyChain::ContainerScanService) }

      before do
        execution.update!(input_data: { "target_type" => "SupplyChain::ContainerImage", "target_id" => container_image.id })
        allow(SupplyChain::ContainerScanService).to receive(:new).and_return(container_service)
        allow(container_service).to receive(:scan!).and_return({ vulnerabilities: [] })
      end

      it "returns container image from account scope" do
        expect(SupplyChain::ContainerScanService).to receive(:new).with(account: account, image: container_image).and_return(container_service)
        described_class.perform_now(execution.id)
      end

      it "handles 'ContainerImage' string type" do
        execution.update!(input_data: { "target_type" => "ContainerImage", "target_id" => container_image.id })
        expect(SupplyChain::ContainerScanService).to receive(:new).with(account: account, image: container_image).and_return(container_service)
        described_class.perform_now(execution.id)
      end
    end

    context "with Repository target" do
      let(:provider) { create(:devops_provider, account: account) }
      let(:repository) { create(:devops_repository, account: account, provider: provider) }
      let(:sbom_service) { instance_double(SupplyChain::SbomGenerationService) }
      let(:generated_sbom) { create(:supply_chain_sbom, account: account) }

      before do
        execution.update!(input_data: { "target_type" => "Devops::Repository", "target_id" => repository.id })
        allow(SupplyChain::SbomGenerationService).to receive(:new).and_return(sbom_service)
        allow(sbom_service).to receive(:generate).and_return(generated_sbom)
      end

      it "returns repository from account scope" do
        expect(SupplyChain::SbomGenerationService).to receive(:new).with(
          account: account,
          repository: repository
        ).and_return(sbom_service)
        expect(sbom_service).to receive(:generate).with(
          source_path: ".",
          format: "cyclonedx_1_5"
        ).and_return(generated_sbom)
        described_class.perform_now(execution.id)
      end

      it "handles 'Repository' string type" do
        execution.update!(input_data: { "target_type" => "Repository", "target_id" => repository.id })
        expect(SupplyChain::SbomGenerationService).to receive(:new).with(
          account: account,
          repository: repository
        ).and_return(sbom_service)
        expect(sbom_service).to receive(:generate).with(
          source_path: ".",
          format: "cyclonedx_1_5"
        ).and_return(generated_sbom)
        described_class.perform_now(execution.id)
      end
    end

    context "with unknown target type" do
      before do
        execution.update!(input_data: { "target_type" => "UnknownType", "target_id" => "some-id" })
      end

      it "returns nil and uses empty results" do
        described_class.perform_now(execution.id)
        execution.reload
        expect(execution.output_data["findings_count"]).to eq(0)
      end
    end

    context "when target is not found in account scope" do
      before do
        execution.update!(input_data: { "target_type" => "SupplyChain::Sbom", "target_id" => "non-existent-id" })
      end

      it "returns nil and uses empty results" do
        described_class.perform_now(execution.id)
        execution.reload
        expect(execution.output_data["findings_count"]).to eq(0)
      end
    end
  end

  describe "#trigger_auto_remediation" do
    let(:vulnerability_service) { instance_double(SupplyChain::VulnerabilityCorrelationService) }
    let(:vulnerability_results) { { total_vulnerabilities: 20 } }

    before do
      instance.update!(configuration: { "auto_remediate" => true })
      allow(SupplyChain::VulnerabilityCorrelationService).to receive(:new).and_return(vulnerability_service)
      allow(vulnerability_service).to receive(:correlate!).and_return(vulnerability_results)
    end

    context "when findings exceed threshold" do
      it "creates RemediationPlan with sbom" do
        expect {
          described_class.perform_now(execution.id)
        }.to change { SupplyChain::RemediationPlan.count }.by(1)

        plan = SupplyChain::RemediationPlan.last
        expect(plan.sbom).to eq(sbom)
        expect(plan.metadata["scan_execution_id"]).to eq(execution.id)
      end

      it "creates plan with auto_fix type" do
        described_class.perform_now(execution.id)
        plan = SupplyChain::RemediationPlan.last
        expect(plan.plan_type).to eq("auto_fix")
      end

      it "creates plan with draft status" do
        described_class.perform_now(execution.id)
        plan = SupplyChain::RemediationPlan.last
        expect(plan.status).to eq("draft")
      end

      it "includes metadata with auto_generated flag" do
        described_class.perform_now(execution.id)
        plan = SupplyChain::RemediationPlan.last
        expect(plan.metadata["auto_generated"]).to eq(true)
      end
    end

    context "with custom remediation threshold" do
      before do
        execution.update!(input_data: execution.input_data.merge("remediation_threshold" => 25))
      end

      it "does not create plan when findings below threshold" do
        expect {
          described_class.perform_now(execution.id)
        }.not_to change { SupplyChain::RemediationPlan.count }
      end
    end

    context "when findings equal threshold" do
      before do
        execution.update!(input_data: execution.input_data.merge("remediation_threshold" => 20))
      end

      it "creates plan" do
        expect {
          described_class.perform_now(execution.id)
        }.to change { SupplyChain::RemediationPlan.count }.by(1)
      end
    end

    context "when results data is empty" do
      let(:vulnerability_results) { { total_vulnerabilities: 0 } }

      it "does not create plan because findings_count is 0" do
        expect {
          described_class.perform_now(execution.id)
        }.not_to change { SupplyChain::RemediationPlan.count }
      end
    end
  end
end
