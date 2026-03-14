# frozen_string_literal: true

require "rails_helper"

RSpec.describe SupplyChain::ContainerScanService, type: :service do
  let(:account) { create(:account) }
  let(:image) { create(:supply_chain_container_image, account: account) }
  let(:options) { {} }
  let(:service) { described_class.new(account: account, image: image, options: options) }

  describe "#initialize" do
    it "initializes with account, image, and options" do
      expect(service.account).to eq(account)
      expect(service.image).to eq(image)
      expect(service.options).to eq({})
    end

    it "converts options to indifferent access" do
      service = described_class.new(account: account, image: image, options: { "scanner" => "trivy" })
      expect(service.options[:scanner]).to eq("trivy")
      expect(service.options["scanner"]).to eq("trivy")
    end

    it "accepts empty options hash" do
      service = described_class.new(account: account, image: image)
      expect(service.options).to eq({})
    end
  end

  describe "SUPPORTED_SCANNERS" do
    it "includes trivy and grype" do
      expect(described_class::SUPPORTED_SCANNERS).to contain_exactly("trivy", "grype")
    end
  end

  describe "#scan!" do
    describe "scanner validation" do
      it "accepts trivy scanner" do
        service = described_class.new(account: account, image: image, options: { scanner: "trivy" })
        expect { service.scan! }.not_to raise_error
      end

      it "accepts grype scanner" do
        service = described_class.new(account: account, image: image, options: { scanner: "grype" })
        expect { service.scan! }.not_to raise_error
      end

      it "raises ScanError for unsupported scanner" do
        service = described_class.new(account: account, image: image, options: { scanner: "unsupported" })
        expect { service.scan! }.to raise_error(
          described_class::ScanError,
          /Unsupported scanner: unsupported/
        )
      end

      it "defaults to trivy when no scanner specified" do
        service = described_class.new(account: account, image: image, options: {})
        scan = service.scan!
        expect(scan.scanner_name).to eq("trivy")
      end
    end

    describe "VulnerabilityScan record creation" do
      it "creates a VulnerabilityScan record" do
        expect {
          service.scan!
        }.to change(SupplyChain::VulnerabilityScan, :count).by(1)
      end

      it "creates scan with correct scanner_name" do
        service = described_class.new(account: account, image: image, options: { scanner: "grype" })
        scan = service.scan!
        expect(scan.scanner_name).to eq("grype")
      end

      it "creates scan with scanner_version for trivy" do
        service = described_class.new(account: account, image: image, options: { scanner: "trivy" })
        scan = service.scan!
        expect(scan.scanner_version).to eq("0.50.0")
      end

      it "creates scan with scanner_version for grype" do
        service = described_class.new(account: account, image: image, options: { scanner: "grype" })
        scan = service.scan!
        expect(scan.scanner_version).to eq("0.74.0")
      end

      it "associates scan with the correct container_image" do
        scan = service.scan!
        expect(scan.container_image).to eq(image)
      end

      it "associates scan with the correct account" do
        scan = service.scan!
        expect(scan.account).to eq(account)
      end

      it "associates scan with triggered_by user when provided" do
        user = create(:user, account: account)
        service = described_class.new(account: account, image: image, options: { user: user })
        scan = service.scan!
        expect(scan.triggered_by).to eq(user)
      end
    end

    describe "scan lifecycle" do
      it "starts the scan by setting status to running" do
        scan = service.scan!
        # Scan should be completed after successful scan
        expect(scan.status).to eq("completed")
      end

      it "sets started_at timestamp" do
        scan = service.scan!
        expect(scan.started_at).to be_present
      end

      it "sets completed_at timestamp on success" do
        scan = service.scan!
        expect(scan.completed_at).to be_present
      end

      it "calculates duration_ms" do
        scan = service.scan!
        expect(scan.duration_ms).to be_present
      end
    end

    describe "updating image vulnerability counts" do
      context "with vulnerabilities found" do
        let(:vulnerabilities) do
          [
            { "severity" => "critical" },
            { "severity" => "critical" },
            { "severity" => "high" },
            { "severity" => "high" },
            { "severity" => "high" },
            { "severity" => "medium" },
            { "severity" => "low" }
          ]
        end

        before do
          allow_any_instance_of(described_class).to receive(:perform_scan).and_return({
            vulnerabilities: vulnerabilities
          })
        end

        it "updates image critical_vuln_count" do
          service.scan!
          expect(image.reload.critical_vuln_count).to eq(2)
        end

        it "updates image high_vuln_count" do
          service.scan!
          expect(image.reload.high_vuln_count).to eq(3)
        end

        it "updates image medium_vuln_count" do
          service.scan!
          expect(image.reload.medium_vuln_count).to eq(1)
        end

        it "updates image low_vuln_count" do
          service.scan!
          expect(image.reload.low_vuln_count).to eq(1)
        end

        it "updates image last_scanned_at" do
          service.scan!
          expect(image.reload.last_scanned_at).to be_present
        end
      end

      context "with no vulnerabilities" do
        before do
          allow_any_instance_of(described_class).to receive(:perform_scan).and_return({
            vulnerabilities: []
          })
        end

        it "sets all counts to zero" do
          service.scan!
          image.reload
          expect(image.critical_vuln_count).to eq(0)
          expect(image.high_vuln_count).to eq(0)
          expect(image.medium_vuln_count).to eq(0)
          expect(image.low_vuln_count).to eq(0)
        end
      end
    end

    describe "policy evaluation after scan" do
      it "evaluates policies after successful scan" do
        expect(service).to receive(:evaluate_policies).with(image).and_call_original
        service.scan!
      end
    end

    describe "scan failure handling" do
      let(:error_message) { "Failed to connect to registry" }

      before do
        allow_any_instance_of(described_class).to receive(:perform_scan).and_raise(
          StandardError.new(error_message)
        )
      end

      it "raises ScanError on failure" do
        expect { service.scan! }.to raise_error(described_class::ScanError)
      end

      it "includes error message in ScanError" do
        expect { service.scan! }.to raise_error(
          described_class::ScanError,
          /Container scan failed: #{error_message}/
        )
      end

      it "marks scan as failed" do
        begin
          service.scan!
        rescue described_class::ScanError
          # Expected
        end

        scan = SupplyChain::VulnerabilityScan.last
        expect(scan.status).to eq("failed")
      end

      it "records error message in scan" do
        begin
          service.scan!
        rescue described_class::ScanError
          # Expected
        end

        scan = SupplyChain::VulnerabilityScan.last
        expect(scan.error_message).to eq(error_message)
      end

      it "sets completed_at even on failure" do
        begin
          service.scan!
        rescue described_class::ScanError
          # Expected
        end

        scan = SupplyChain::VulnerabilityScan.last
        expect(scan.completed_at).to be_present
      end

      it "calculates duration_ms even on failure" do
        begin
          service.scan!
        rescue described_class::ScanError
          # Expected
        end

        scan = SupplyChain::VulnerabilityScan.last
        expect(scan.duration_ms).to be_present
      end
    end

    describe "scan returns VulnerabilityScan record" do
      it "returns the completed scan record" do
        scan = service.scan!
        expect(scan).to be_a(SupplyChain::VulnerabilityScan)
        expect(scan.persisted?).to be true
      end
    end
  end

  describe "#evaluate_policies" do
    context "with no active policies" do
      it "returns passed: true" do
        result = service.evaluate_policies
        expect(result[:passed]).to be true
      end

      it "returns empty policy_results" do
        result = service.evaluate_policies
        expect(result[:policy_results]).to be_empty
      end
    end

    context "with all policies passing" do
      let!(:policy1) do
        create(:supply_chain_image_policy, :active, :vulnerability_threshold,
               account: account,
               max_critical_vulns: 10,
               max_high_vulns: 50)
      end
      let!(:policy2) do
        create(:supply_chain_image_policy, :active, :registry_allowlist,
               account: account,
               rules: { "allowed_registries" => [ image.registry ] })
      end
      let(:image) { create(:supply_chain_container_image, :clean, account: account) }

      it "returns passed: true" do
        result = service.evaluate_policies
        expect(result[:passed]).to be true
      end

      it "includes results for each policy" do
        result = service.evaluate_policies
        expect(result[:policy_results].length).to eq(2)
      end

      it "verifies image when all policies pass" do
        image.update!(status: "unverified")
        service.evaluate_policies
        expect(image.reload.status).to eq("verified")
      end

      it "does not verify image if already verified" do
        image.update!(status: "verified")
        expect(image).not_to receive(:verify!)
        service.evaluate_policies
      end
    end

    context "with blocking policy failure" do
      let!(:blocking_policy) do
        create(:supply_chain_image_policy, :active, :blocking, :vulnerability_threshold,
               account: account,
               max_critical_vulns: 0,
               max_high_vulns: 0)
      end
      let(:image) do
        create(:supply_chain_container_image,
               account: account,
               critical_vuln_count: 5,
               high_vuln_count: 10)
      end

      it "returns passed: false" do
        result = service.evaluate_policies
        expect(result[:passed]).to be false
      end

      it "quarantines the image" do
        service.evaluate_policies
        expect(image.reload.status).to eq("quarantined")
      end

      it "includes quarantine reason in metadata" do
        service.evaluate_policies
        expect(image.reload.metadata["quarantine_reason"]).to eq("Failed policy evaluation")
      end

      it "includes failing policy in results" do
        result = service.evaluate_policies
        failed_result = result[:policy_results].find { |r| r[:passed] == false }
        expect(failed_result[:policy_id]).to eq(blocking_policy.id)
      end
    end

    context "with non-blocking policy failure" do
      let!(:warning_policy) do
        create(:supply_chain_image_policy, :active, :warning, :vulnerability_threshold,
               account: account,
               max_critical_vulns: 0,
               max_high_vulns: 0)
      end
      let(:image) do
        create(:supply_chain_container_image,
               account: account,
               critical_vuln_count: 5,
               high_vuln_count: 10)
      end

      it "returns passed: true (non-blocking failure does not affect overall result)" do
        result = service.evaluate_policies
        expect(result[:passed]).to be true
      end

      it "does not quarantine the image" do
        original_status = image.status
        service.evaluate_policies
        expect(image.reload.status).not_to eq("quarantined")
      end

      it "includes policy result with passed: false" do
        result = service.evaluate_policies
        policy_result = result[:policy_results].find { |r| r[:policy_id] == warning_policy.id }
        expect(policy_result[:passed]).to be false
      end
    end

    context "with mixed blocking and non-blocking policies" do
      let!(:blocking_policy) do
        create(:supply_chain_image_policy, :active, :blocking, :vulnerability_threshold,
               account: account,
               max_critical_vulns: 0,
               priority: 10)
      end
      let!(:warning_policy) do
        create(:supply_chain_image_policy, :active, :warning, :vulnerability_threshold,
               account: account,
               max_high_vulns: 0,
               priority: 5)
      end
      let(:image) do
        create(:supply_chain_container_image,
               account: account,
               critical_vuln_count: 1,
               high_vuln_count: 5)
      end

      it "returns passed: false when blocking policy fails" do
        result = service.evaluate_policies
        expect(result[:passed]).to be false
      end

      it "quarantines image on blocking policy failure" do
        service.evaluate_policies
        expect(image.reload.status).to eq("quarantined")
      end
    end

    context "with signature required policy" do
      let!(:signature_policy) do
        create(:supply_chain_image_policy, :active, :blocking, :signature_required,
               account: account,
               require_signature: true)
      end

      context "when image is signed" do
        let(:image) { create(:supply_chain_container_image, account: account, is_signed: true) }

        it "returns passed: true" do
          result = service.evaluate_policies
          expect(result[:passed]).to be true
        end
      end

      context "when image is not signed" do
        let(:image) { create(:supply_chain_container_image, account: account, is_signed: false) }

        it "returns passed: false" do
          result = service.evaluate_policies
          expect(result[:passed]).to be false
        end

        it "quarantines the image" do
          service.evaluate_policies
          expect(image.reload.status).to eq("quarantined")
        end
      end
    end

    context "with skipped policies (not matching image)" do
      let!(:policy) do
        create(:supply_chain_image_policy, :active, :blocking, :registry_allowlist,
               account: account,
               match_rules: { "registries" => [ "other-registry.io" ] })
      end

      it "returns passed: true when policy is skipped" do
        result = service.evaluate_policies
        expect(result[:passed]).to be true
      end

      it "marks result as skipped" do
        result = service.evaluate_policies
        policy_result = result[:policy_results].first
        expect(policy_result[:skipped]).to be true
      end

      it "includes skip reason" do
        result = service.evaluate_policies
        policy_result = result[:policy_results].first
        expect(policy_result[:reason]).to be_present
      end
    end

    context "when evaluating specific image" do
      let(:other_image) { create(:supply_chain_container_image, :clean, account: account) }
      let!(:policy) do
        create(:supply_chain_image_policy, :active, :blocking, :vulnerability_threshold,
               account: account,
               max_critical_vulns: 0)
      end

      it "evaluates policies against the provided image" do
        result = service.evaluate_policies(other_image)
        expect(result[:passed]).to be true
      end

      it "updates the provided image status" do
        other_image.update!(status: "unverified")
        service.evaluate_policies(other_image)
        expect(other_image.reload.status).to eq("verified")
      end
    end

    context "with inactive policies" do
      let!(:inactive_policy) do
        create(:supply_chain_image_policy, :inactive, :blocking, :vulnerability_threshold,
               account: account,
               max_critical_vulns: 0)
      end
      let(:image) do
        create(:supply_chain_container_image, account: account, critical_vuln_count: 5)
      end

      it "does not evaluate inactive policies" do
        result = service.evaluate_policies
        expect(result[:passed]).to be true
        expect(result[:policy_results]).to be_empty
      end
    end

    context "policy ordering" do
      let!(:low_priority_policy) do
        create(:supply_chain_image_policy, :active, :blocking, :registry_allowlist,
               account: account,
               priority: 1,
               rules: { "allowed_registries" => [ image.registry ] })
      end
      let!(:high_priority_policy) do
        create(:supply_chain_image_policy, :active, :blocking, :vulnerability_threshold,
               account: account,
               priority: 10,
               max_critical_vulns: 100)
      end

      it "evaluates policies in order by priority" do
        result = service.evaluate_policies
        policy_ids = result[:policy_results].map { |r| r[:policy_id] }
        expect(policy_ids).to eq([ high_priority_policy.id, low_priority_policy.id ])
      end
    end
  end

  describe "error handling and edge cases" do
    context "with nil image" do
      let(:service) { described_class.new(account: account, image: nil, options: options) }

      it "raises error when scanning nil image" do
        expect { service.scan! }.to raise_error(ActiveRecord::RecordInvalid, /Container image must exist/)
      end
    end

    context "with image belonging to different account" do
      let(:other_account) { create(:account) }
      let(:other_image) { create(:supply_chain_container_image, account: other_account) }
      let(:service) { described_class.new(account: account, image: other_image, options: options) }

      it "still creates scan with provided account" do
        scan = service.scan!
        expect(scan.account).to eq(account)
      end
    end

    describe "scanner-specific behavior" do
      describe "trivy scanner" do
        let(:options) { { scanner: "trivy" } }

        it "logs scanning with trivy" do
          expect(Rails.logger).to receive(:info).with(/Scanning.*with Trivy/)
          service.scan!
        end
      end

      describe "grype scanner" do
        let(:options) { { scanner: "grype" } }

        it "logs scanning with grype" do
          expect(Rails.logger).to receive(:info).with(/Scanning.*with Grype/)
          service.scan!
        end
      end
    end

    describe "full_reference usage" do
      it "uses image full_reference for scanning" do
        expected_reference = "#{image.registry}/#{image.repository}:#{image.tag}"
        expect_any_instance_of(described_class).to receive(:perform_scan).with("trivy", expected_reference).and_call_original
        service.scan!
      end
    end
  end

  describe "integration scenarios" do
    context "complete scan workflow with policy evaluation" do
      let!(:strict_policy) do
        create(:supply_chain_image_policy, :active, :blocking, :vulnerability_threshold,
               account: account,
               max_critical_vulns: 0,
               max_high_vulns: 5)
      end
      let(:image) { create(:supply_chain_container_image, account: account, status: "unverified") }

      context "when scan finds no critical vulnerabilities" do
        before do
          allow_any_instance_of(described_class).to receive(:perform_scan).and_return({
            vulnerabilities: [
              { "severity" => "high" },
              { "severity" => "medium" }
            ]
          })
        end

        it "completes scan and verifies image" do
          scan = service.scan!
          expect(scan.status).to eq("completed")
          expect(image.reload.status).to eq("verified")
        end
      end

      context "when scan finds critical vulnerabilities" do
        before do
          allow_any_instance_of(described_class).to receive(:perform_scan).and_return({
            vulnerabilities: [
              { "severity" => "critical" },
              { "severity" => "critical" }
            ]
          })
        end

        it "completes scan and quarantines image" do
          scan = service.scan!
          expect(scan.status).to eq("completed")
          expect(image.reload.status).to eq("quarantined")
        end
      end
    end

    context "multiple scans of same image" do
      it "creates separate scan records for each scan" do
        expect {
          service.scan!
          service.scan!
        }.to change(SupplyChain::VulnerabilityScan, :count).by(2)
      end

      it "updates image counts with latest scan results" do
        allow_any_instance_of(described_class).to receive(:perform_scan).and_return({
          vulnerabilities: [ { "severity" => "critical" } ]
        })
        service.scan!
        expect(image.reload.critical_vuln_count).to eq(1)

        allow_any_instance_of(described_class).to receive(:perform_scan).and_return({
          vulnerabilities: []
        })
        service.scan!
        expect(image.reload.critical_vuln_count).to eq(0)
      end
    end
  end

  describe "ScanError class" do
    it "is defined as a custom error class" do
      expect(described_class::ScanError).to be < StandardError
    end

    it "can be raised with custom message" do
      expect { raise described_class::ScanError, "Custom error" }.to raise_error(
        described_class::ScanError,
        "Custom error"
      )
    end
  end
end
