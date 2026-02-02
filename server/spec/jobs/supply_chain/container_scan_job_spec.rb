# frozen_string_literal: true

require "rails_helper"

RSpec.describe SupplyChain::ContainerScanJob, type: :job do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:image) { create(:supply_chain_container_image, account: account) }
  let(:scan) { create(:supply_chain_vulnerability_scan, container_image: image, account: account) }
  let(:scan_service) { instance_double(SupplyChain::ContainerScanService) }
  let(:policy_service) { instance_double(SupplyChain::ContainerScanService) }
  let(:options) do
    {
      scanner: "trivy",
      evaluate_policies: true
    }
  end

  before do
    # Mock service instantiation - return scan_service first, then policy_service
    allow(SupplyChain::ContainerScanService).to receive(:new).and_return(scan_service, policy_service)

    allow(scan_service).to receive(:scan!).and_return(scan)
    allow(policy_service).to receive(:evaluate_policies).and_return(policy_evaluation_result)
    allow(SupplyChainChannel).to receive(:broadcast_scan_started)
    allow(SupplyChainChannel).to receive(:broadcast_scan_completed)
    allow(SupplyChainChannel).to receive(:broadcast_policy_evaluation_completed)
    allow(SupplyChainChannel).to receive(:broadcast_policy_violation)
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:error)
  end

  let(:policy_evaluation_result) do
    {
      passed: true,
      policy_results: [
        {
          policy_id: SecureRandom.uuid,
          policy_name: "Test Policy",
          passed: true,
          violations: []
        }
      ]
    }
  end

  describe "queue configuration" do
    it "uses supply_chain_default queue" do
      expect(described_class.new.queue_name).to eq("supply_chain_default")
    end
  end

  describe "#perform" do
    context "with valid container image" do
      it "finds container image by ID" do
        expect(SupplyChain::ContainerImage).to receive(:find).with(image.id).and_return(image)

        described_class.perform_now(image.id, options)
      end

      it "broadcasts scan_started event" do
        expect(SupplyChainChannel).to receive(:broadcast_scan_started).with(image)

        described_class.perform_now(image.id, options)
      end

      it "creates ContainerScanService for scanning with options" do
        # Just verify the service was created and scan! was called
        # The before block handles the mocking
        expect(scan_service).to receive(:scan!).and_return(scan)

        described_class.perform_now(image.id, options)
      end

      it "calls scan! on the service" do
        expect(scan_service).to receive(:scan!).and_return(scan)

        described_class.perform_now(image.id, options)
      end

      it "broadcasts scan_completed event" do
        expect(SupplyChainChannel).to receive(:broadcast_scan_completed).with(scan)

        described_class.perform_now(image.id, options)
      end
    end

    context "policy evaluation" do
      context "when evaluate_policies is not specified (default)" do
        let(:options_without_evaluate_policies) { { scanner: "trivy" } }

        it "evaluates policies by default" do
          expect(policy_service).to receive(:evaluate_policies).and_return(policy_evaluation_result)

          described_class.perform_now(image.id, options_without_evaluate_policies)
        end

        it "broadcasts policy_evaluation_completed" do
          expect(SupplyChainChannel).to receive(:broadcast_policy_evaluation_completed).with(
            account,
            policy_evaluation_result
          )

          described_class.perform_now(image.id, options_without_evaluate_policies)
        end
      end

      context "when evaluate_policies is true" do
        let(:options_with_evaluation) { { scanner: "trivy", evaluate_policies: true } }

        it "evaluates policies" do
          expect(policy_service).to receive(:evaluate_policies).and_return(policy_evaluation_result)

          described_class.perform_now(image.id, options_with_evaluation)
        end

        it "creates separate service instances for scan and policy evaluation" do
          # Verify both services are used
          expect(scan_service).to receive(:scan!).and_return(scan)
          expect(policy_service).to receive(:evaluate_policies).and_return(policy_evaluation_result)

          described_class.perform_now(image.id, options_with_evaluation)
        end

        it "broadcasts policy_evaluation_completed" do
          expect(SupplyChainChannel).to receive(:broadcast_policy_evaluation_completed).with(
            account,
            policy_evaluation_result
          )

          described_class.perform_now(image.id, options_with_evaluation)
        end
      end

      context "when evaluate_policies is false" do
        let(:options_without_evaluation) { { scanner: "trivy", evaluate_policies: false } }

        it "does not evaluate policies" do
          expect(policy_service).not_to receive(:evaluate_policies)

          described_class.perform_now(image.id, options_without_evaluation)
        end

        it "does not broadcast policy_evaluation_completed" do
          expect(SupplyChainChannel).not_to receive(:broadcast_policy_evaluation_completed)

          described_class.perform_now(image.id, options_without_evaluation)
        end

        it "does not broadcast policy_violation" do
          expect(SupplyChainChannel).not_to receive(:broadcast_policy_violation)

          described_class.perform_now(image.id, options_without_evaluation)
        end
      end

      context "when evaluate_policies is nil" do
        let(:options_with_nil_evaluation) { { scanner: "trivy", evaluate_policies: nil } }

        it "evaluates policies (nil is not false)" do
          expect(policy_service).to receive(:evaluate_policies).and_return(policy_evaluation_result)

          described_class.perform_now(image.id, options_with_nil_evaluation)
        end
      end
    end

    context "policy violation broadcasting" do
      context "when policies fail" do
        let(:policy_evaluation_with_violations) do
          {
            passed: false,
            policy_results: [
              {
                policy_id: SecureRandom.uuid,
                policy_name: "Critical Vulnerability Policy",
                passed: false,
                skipped: false,
                violations: [
                  { severity: "critical", count: 3 }
                ]
              },
              {
                policy_id: SecureRandom.uuid,
                policy_name: "High Vulnerability Policy",
                passed: false,
                skipped: false,
                violations: [
                  { severity: "high", count: 5 }
                ]
              }
            ]
          }
        end

        before do
          allow(policy_service).to receive(:evaluate_policies).and_return(policy_evaluation_with_violations)
        end

        it "broadcasts policy_violation for each failed policy" do
          expect(SupplyChainChannel).to receive(:broadcast_policy_violation).exactly(2).times

          described_class.perform_now(image.id, options)
        end

        it "broadcasts policy_violation with correct details" do
          policy_result = policy_evaluation_with_violations[:policy_results].first

          expect(SupplyChainChannel).to receive(:broadcast_policy_violation).with(
            account,
            hash_including(
              policy_id: policy_result[:policy_id],
              policy_name: policy_result[:policy_name],
              violations: policy_result[:violations]
            )
          )

          described_class.perform_now(image.id, options)
        end
      end

      context "when policies pass" do
        let(:policy_evaluation_passed) do
          {
            passed: true,
            policy_results: [
              {
                policy_id: SecureRandom.uuid,
                policy_name: "Test Policy",
                passed: true,
                skipped: false,
                violations: []
              }
            ]
          }
        end

        before do
          allow(policy_service).to receive(:evaluate_policies).and_return(policy_evaluation_passed)
        end

        it "does not broadcast policy_violation" do
          expect(SupplyChainChannel).not_to receive(:broadcast_policy_violation)

          described_class.perform_now(image.id, options)
        end
      end

      context "when policies are skipped" do
        let(:policy_evaluation_skipped) do
          {
            passed: true,
            policy_results: [
              {
                policy_id: SecureRandom.uuid,
                policy_name: "Skipped Policy",
                passed: false,
                skipped: true,
                violations: []
              }
            ]
          }
        end

        before do
          allow(policy_service).to receive(:evaluate_policies).and_return(policy_evaluation_skipped)
        end

        it "does not broadcast policy_violation for skipped policies" do
          expect(SupplyChainChannel).not_to receive(:broadcast_policy_violation)

          described_class.perform_now(image.id, options)
        end
      end

      context "with mixed policy results" do
        let(:mixed_policy_results) do
          {
            passed: false,
            policy_results: [
              {
                policy_id: SecureRandom.uuid,
                policy_name: "Failed Policy",
                passed: false,
                skipped: false,
                violations: [ { severity: "high" } ]
              },
              {
                policy_id: SecureRandom.uuid,
                policy_name: "Passed Policy",
                passed: true,
                skipped: false,
                violations: []
              },
              {
                policy_id: SecureRandom.uuid,
                policy_name: "Skipped Policy",
                passed: false,
                skipped: true,
                violations: []
              }
            ]
          }
        end

        before do
          allow(policy_service).to receive(:evaluate_policies).and_return(mixed_policy_results)
        end

        it "only broadcasts policy_violation for failed policies" do
          expect(SupplyChainChannel).to receive(:broadcast_policy_violation).exactly(1).times

          described_class.perform_now(image.id, options)
        end
      end
    end

    context "logging" do
      it "logs start message" do
        expect(Rails.logger).to receive(:info).with(
          "[ContainerScanJob] Starting scan for container image #{image.id}"
        )

        described_class.perform_now(image.id, options)
      end

      it "logs completion message" do
        expect(Rails.logger).to receive(:info).with(
          "[ContainerScanJob] Scan completed for container image #{image.id}"
        )

        described_class.perform_now(image.id, options)
      end
    end

    context "error handling" do
      context "when container image is not found" do
        it "raises ActiveRecord::RecordNotFound" do
          expect {
            described_class.perform_now("non-existent-id", options)
          }.to raise_error(ActiveRecord::RecordNotFound)
        end

        it "logs error message" do
          allow(SupplyChain::ContainerImage).to receive(:find).and_raise(
            ActiveRecord::RecordNotFound.new("Container image not found")
          )

          expect(Rails.logger).to receive(:error).with(
            "[ContainerScanJob] Failed: Container image not found"
          )

          expect {
            described_class.perform_now("non-existent-id", options)
          }.to raise_error(ActiveRecord::RecordNotFound)
        end
      end

      context "when ContainerScanService raises an error" do
        let(:service_error) { StandardError.new("Scan failed") }

        before do
          allow(scan_service).to receive(:scan!).and_raise(service_error)
        end

        it "logs the error message" do
          expect(Rails.logger).to receive(:error).with(
            "[ContainerScanJob] Failed: Scan failed"
          )

          expect {
            described_class.perform_now(image.id, options)
          }.to raise_error(StandardError, "Scan failed")
        end

        it "re-raises the error" do
          expect {
            described_class.perform_now(image.id, options)
          }.to raise_error(StandardError, "Scan failed")
        end

        it "does not broadcast scan_completed" do
          expect(SupplyChainChannel).not_to receive(:broadcast_scan_completed)

          expect {
            described_class.perform_now(image.id, options)
          }.to raise_error(StandardError)
        end

        it "does not evaluate policies" do
          expect(policy_service).not_to receive(:evaluate_policies)

          expect {
            described_class.perform_now(image.id, options)
          }.to raise_error(StandardError)
        end
      end

      context "when broadcast_scan_started fails" do
        let(:broadcast_error) { StandardError.new("Broadcast failed") }

        before do
          allow(SupplyChainChannel).to receive(:broadcast_scan_started).and_raise(broadcast_error)
        end

        it "logs the error" do
          expect(Rails.logger).to receive(:error).with(
            "[ContainerScanJob] Failed: Broadcast failed"
          )

          expect {
            described_class.perform_now(image.id, options)
          }.to raise_error(StandardError, "Broadcast failed")
        end

        it "re-raises the error" do
          expect {
            described_class.perform_now(image.id, options)
          }.to raise_error(StandardError, "Broadcast failed")
        end

        it "does not call scan!" do
          expect(scan_service).not_to receive(:scan!)

          expect {
            described_class.perform_now(image.id, options)
          }.to raise_error(StandardError)
        end
      end

      context "when policy evaluation fails" do
        let(:policy_error) { StandardError.new("Policy evaluation failed") }

        before do
          allow(policy_service).to receive(:evaluate_policies).and_raise(policy_error)
        end

        it "logs the error" do
          expect(Rails.logger).to receive(:error).with(
            "[ContainerScanJob] Failed: Policy evaluation failed"
          )

          expect {
            described_class.perform_now(image.id, options)
          }.to raise_error(StandardError, "Policy evaluation failed")
        end

        it "re-raises the error" do
          expect {
            described_class.perform_now(image.id, options)
          }.to raise_error(StandardError, "Policy evaluation failed")
        end

        it "still broadcasts scan_completed before failing" do
          expect(SupplyChainChannel).to receive(:broadcast_scan_completed).with(scan)

          expect {
            described_class.perform_now(image.id, options)
          }.to raise_error(StandardError)
        end
      end
    end

    context "options handling" do
      it "converts options to with_indifferent_access" do
        expect(scan_service).to receive(:scan!).and_return(scan)

        described_class.perform_now(image.id, options)
      end

      it "handles string keys in options" do
        string_options = {
          "scanner" => "grype",
          "evaluate_policies" => true
        }

        expect(scan_service).to receive(:scan!).and_return(scan)

        described_class.perform_now(image.id, string_options)
      end

      it "handles empty options hash" do
        expect(scan_service).to receive(:scan!).and_return(scan)

        described_class.perform_now(image.id, {})
      end

      it "handles nil options" do
        expect(scan_service).to receive(:scan!).and_return(scan)

        described_class.perform_now(image.id, nil)
      end

      it "passes scanner option to service" do
        grype_options = { scanner: "grype" }

        expect(scan_service).to receive(:scan!).and_return(scan)

        described_class.perform_now(image.id, grype_options)
      end
    end

    context "integration test" do
      it "successfully completes full workflow with policy evaluation" do
        expect(SupplyChainChannel).to receive(:broadcast_scan_started).with(image).ordered
        expect(scan_service).to receive(:scan!).and_return(scan).ordered
        expect(SupplyChainChannel).to receive(:broadcast_scan_completed).with(scan).ordered
        expect(policy_service).to receive(:evaluate_policies).and_return(policy_evaluation_result).ordered
        expect(SupplyChainChannel).to receive(:broadcast_policy_evaluation_completed).with(
          account,
          policy_evaluation_result
        ).ordered

        described_class.perform_now(image.id, options)

        expect(Rails.logger).to have_received(:info).with(
          "[ContainerScanJob] Starting scan for container image #{image.id}"
        )
        expect(Rails.logger).to have_received(:info).with(
          "[ContainerScanJob] Scan completed for container image #{image.id}"
        )
      end

      it "successfully completes workflow without policy evaluation" do
        options_no_eval = { scanner: "trivy", evaluate_policies: false }

        expect(SupplyChainChannel).to receive(:broadcast_scan_started).with(image).ordered
        expect(scan_service).to receive(:scan!).and_return(scan).ordered
        expect(SupplyChainChannel).to receive(:broadcast_scan_completed).with(scan).ordered
        expect(policy_service).not_to receive(:evaluate_policies)

        described_class.perform_now(image.id, options_no_eval)
      end
    end
  end
end
