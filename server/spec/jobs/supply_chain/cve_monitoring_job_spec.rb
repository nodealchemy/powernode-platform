# frozen_string_literal: true

require "rails_helper"

RSpec.describe SupplyChain::CveMonitoringJob, type: :job do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  before do
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:error)
    allow(SupplyChainChannel).to receive(:broadcast_cve_alert)
  end

  describe "queue configuration" do
    it "uses supply_chain_monitoring queue" do
      expect(described_class.new.queue_name).to eq("supply_chain_monitoring")
    end
  end

  describe "#perform" do
    context "with account_id provided" do
      let!(:sbom) { create(:supply_chain_sbom, account: account, status: "completed") }
      let!(:component) { create(:supply_chain_sbom_component, sbom: sbom, account: account) }
      let!(:vulnerability) do
        create(:supply_chain_sbom_vulnerability,
          sbom: sbom,
          component: component,
          account: account,
          severity: "critical",
          created_at: 2.hours.ago)
      end

      it "finds the account by account_id" do
        expect(Account).to receive(:find).with(account.id).and_return(account)
        described_class.perform_now(account.id)
      end

      it "calls monitor_account with the account" do
        job = described_class.new
        allow(job).to receive(:monitor_account)
        job.perform(account.id)
        expect(job).to have_received(:monitor_account).with(account)
      end

      it "logs monitoring start message" do
        described_class.perform_now(account.id)
        expect(Rails.logger).to have_received(:info).with("[CveMonitoringJob] Monitoring CVEs for account #{account.id}")
      end

      it "raises error when account is not found" do
        expect {
          described_class.perform_now("non-existent-id")
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    context "without account_id" do
      let!(:monitor1) { create(:supply_chain_cve_monitor, account: account, is_active: true, created_by: user) }
      let!(:monitor2) { create(:supply_chain_cve_monitor, account: account, is_active: true, created_by: user) }
      let!(:inactive_monitor) { create(:supply_chain_cve_monitor, account: account, is_active: false, created_by: user) }

      it "iterates through all active CveMonitors" do
        described_class.perform_now

        expect(Rails.logger).to have_received(:info).with("[CveMonitoringJob] Running CVE monitor #{monitor1.id}")
        expect(Rails.logger).to have_received(:info).with("[CveMonitoringJob] Running CVE monitor #{monitor2.id}")
      end

      it "does not process inactive monitors" do
        described_class.perform_now

        expect(Rails.logger).not_to have_received(:info).with("[CveMonitoringJob] Running CVE monitor #{inactive_monitor.id}")
      end

      it "calls monitor_for_cve_monitor for each active monitor" do
        job = described_class.new
        allow(job).to receive(:monitor_for_cve_monitor)
        job.perform(nil)

        expect(job).to have_received(:monitor_for_cve_monitor).with(monitor1)
        expect(job).to have_received(:monitor_for_cve_monitor).with(monitor2)
        expect(job).to have_received(:monitor_for_cve_monitor).exactly(2).times
      end
    end
  end

  describe "#monitor_account" do
    let!(:active_sbom) { create(:supply_chain_sbom, account: account, status: "completed") }
    let!(:inactive_sbom) { create(:supply_chain_sbom, account: account, status: "archived") }
    let!(:deployed_image) { create(:supply_chain_container_image, account: account, is_deployed: true) }
    let!(:undeployed_image) { create(:supply_chain_container_image, account: account, is_deployed: false) }
    let!(:component) { create(:supply_chain_sbom_component, sbom: active_sbom, account: account) }
    let!(:new_vulnerability) do
      create(:supply_chain_sbom_vulnerability,
        sbom: active_sbom,
        component: component,
        account: account,
        severity: "critical",
        created_at: 2.hours.ago)
    end

    it "filters only active SBOMs" do
      job = described_class.new
      allow(job).to receive(:check_for_new_cves).and_return([])
      job.send(:monitor_account, account)

      expect(job).to have_received(:check_for_new_cves) do |sboms|
        expect(sboms).to include(active_sbom)
        expect(sboms).not_to include(inactive_sbom)
      end
    end

    it "logs the start of monitoring" do
      described_class.perform_now(account.id)
      expect(Rails.logger).to have_received(:info).with("[CveMonitoringJob] Monitoring CVEs for account #{account.id}")
    end

    it "checks for new CVEs" do
      job = described_class.new
      allow(job).to receive(:check_for_new_cves).and_return([])
      job.send(:monitor_account, account)

      expect(job).to have_received(:check_for_new_cves)
    end

    it "broadcasts CVE alerts for each new CVE" do
      described_class.perform_now(account.id)

      expect(SupplyChainChannel).to have_received(:broadcast_cve_alert).with(account, anything)
    end

    it "logs the count of new CVEs found" do
      described_class.perform_now(account.id)

      expect(Rails.logger).to have_received(:info).with(match(/Found \d+ new CVEs for account #{account.id}/))
    end
  end

  describe "#monitor_for_cve_monitor" do
    context "with account_wide scope" do
      let!(:monitor) { create(:supply_chain_cve_monitor, created_by: user, account: account, scope_type: "account_wide") }

      it "calls check_account_wide" do
        job = described_class.new
        allow(job).to receive(:check_account_wide)
        job.send(:monitor_for_cve_monitor, monitor)

        expect(job).to have_received(:check_account_wide).with(monitor)
      end

      it "updates last_run_at" do
        freeze_time do
          described_class.perform_now
          expect(monitor.reload.last_run_at).to be_within(1.second).of(Time.current)
        end
      end

      it "logs the monitor run" do
        described_class.perform_now
        expect(Rails.logger).to have_received(:info).with("[CveMonitoringJob] Running CVE monitor #{monitor.id}")
      end
    end

    context "with repository scope" do
      let!(:monitor) { create(:supply_chain_cve_monitor, :repository_scope, account: account, created_by: user) }

      it "calls check_repository_scope" do
        job = described_class.new
        allow(job).to receive(:check_repository_scope)
        job.send(:monitor_for_cve_monitor, monitor)

        expect(job).to have_received(:check_repository_scope).with(monitor)
      end

      it "updates last_run_at" do
        freeze_time do
          described_class.perform_now
          expect(monitor.reload.last_run_at).to be_within(1.second).of(Time.current)
        end
      end
    end

    context "with image scope" do
      let!(:monitor) { create(:supply_chain_cve_monitor, :image_scope, created_by: user, account: account) }

      it "calls check_image_scope" do
        job = described_class.new
        allow(job).to receive(:check_image_scope)
        job.send(:monitor_for_cve_monitor, monitor)

        expect(job).to have_received(:check_image_scope).with(monitor)
      end

      it "updates last_run_at" do
        freeze_time do
          described_class.perform_now
          expect(monitor.reload.last_run_at).to be_within(1.second).of(Time.current)
        end
      end
    end

    context "error handling" do
      let!(:monitor) { create(:supply_chain_cve_monitor, created_by: user, account: account) }
      let(:error_message) { "Monitor check failed" }

      before do
        allow_any_instance_of(described_class).to receive(:check_account_wide).and_raise(StandardError.new(error_message))
      end

      it "logs the error with monitor id" do
        described_class.perform_now

        expect(Rails.logger).to have_received(:error).with("[CveMonitoringJob] Monitor #{monitor.id} failed: #{error_message}")
      end

      it "does not re-raise the error" do
        expect {
          described_class.perform_now
        }.not_to raise_error
      end

      it "does not update last_run_at when error occurs" do
        original_check_at = monitor.last_run_at
        described_class.perform_now

        expect(monitor.reload.last_run_at).to eq(original_check_at)
      end

      it "continues processing other monitors" do
        monitor2 = create(:supply_chain_cve_monitor, created_by: user, account: account)

        described_class.perform_now

        expect(Rails.logger).to have_received(:info).with("[CveMonitoringJob] Running CVE monitor #{monitor.id}")
        expect(Rails.logger).to have_received(:info).with("[CveMonitoringJob] Running CVE monitor #{monitor2.id}")
      end
    end
  end

  describe "#check_for_new_cves" do
    let!(:sbom) { create(:supply_chain_sbom, account: account, status: "completed") }
    let!(:component) { create(:supply_chain_sbom_component, sbom: sbom, account: account, name: "test-package", version: "1.0.0") }
    let!(:old_vulnerability) do
      create(:supply_chain_sbom_vulnerability,
        sbom: sbom,
        component: component,
        account: account,
        severity: "critical",
        vulnerability_id: "CVE-2023-1234",
        cvss_score: 9.8,
        created_at: 3.days.ago)
    end
    let!(:new_vulnerability) do
      create(:supply_chain_sbom_vulnerability,
        sbom: sbom,
        component: component,
        account: account,
        severity: "high",
        vulnerability_id: "CVE-2024-5678",
        cvss_score: 7.5,
        created_at: 2.hours.ago)
    end

    it "creates VulnerabilityCorrelationService for each SBOM" do
      expect(SupplyChain::VulnerabilityCorrelationService).to receive(:new).with(sbom: sbom).and_call_original

      job = described_class.new
      job.send(:check_for_new_cves, [ sbom ])
    end

    it "returns only vulnerabilities created within 1 day" do
      job = described_class.new
      new_cves = job.send(:check_for_new_cves, [ sbom ])

      expect(new_cves.length).to eq(1)
      expect(new_cves.first[:vulnerability_id]).to eq("CVE-2024-5678")
    end

    it "includes all required CVE details" do
      job = described_class.new
      new_cves = job.send(:check_for_new_cves, [ sbom ])

      cve = new_cves.first
      expect(cve).to include(
        vulnerability_id: "CVE-2024-5678",
        severity: "high",
        cvss_score: 7.5,
        affected_component: "test-package",
        affected_version: "1.0.0",
        sbom_id: sbom.id,
        sbom_name: sbom.name
      )
    end

    it "returns empty array when no new vulnerabilities" do
      old_vulnerability.update!(created_at: 3.days.ago)
      new_vulnerability.update!(created_at: 3.days.ago)

      job = described_class.new
      new_cves = job.send(:check_for_new_cves, [ sbom ])

      expect(new_cves).to be_empty
    end

    it "handles multiple SBOMs" do
      sbom2 = create(:supply_chain_sbom, account: account, status: "completed")
      component2 = create(:supply_chain_sbom_component, sbom: sbom2, account: account)
      create(:supply_chain_sbom_vulnerability,
        sbom: sbom2,
        component: component2,
        account: account,
        severity: "medium",
        created_at: 2.hours.ago)

      job = described_class.new
      new_cves = job.send(:check_for_new_cves, [ sbom, sbom2 ])

      expect(new_cves.length).to eq(2)
    end
  end

  describe "#check_account_wide" do
    let(:monitor) { create(:supply_chain_cve_monitor, created_by: user, account: account, scope_type: "account_wide", min_severity: "high") }
    let!(:sbom) { create(:supply_chain_sbom, account: account) }
    let!(:component) { create(:supply_chain_sbom_component, sbom: sbom, account: account) }

    context "with critical vulnerabilities" do
      let!(:critical_vuln) do
        create(:supply_chain_sbom_vulnerability,
          sbom: sbom,
          component: component,
          account: account,
          severity: "critical")
      end

      it "creates alerts for critical vulnerabilities when min_severity is critical" do
        monitor.update!(min_severity: "critical")
        described_class.perform_now

        expect(SupplyChainChannel).to have_received(:broadcast_cve_alert).with(account, hash_including(severity: "critical"))
      end

      it "creates alerts for critical vulnerabilities when min_severity is high" do
        monitor.update!(min_severity: "high")
        described_class.perform_now

        expect(SupplyChainChannel).to have_received(:broadcast_cve_alert).with(account, hash_including(severity: "critical"))
      end

      it "creates alerts for critical vulnerabilities when min_severity is medium" do
        monitor.update!(min_severity: "medium")
        described_class.perform_now

        expect(SupplyChainChannel).to have_received(:broadcast_cve_alert).with(account, hash_including(severity: "critical"))
      end

      it "creates alerts for critical vulnerabilities when min_severity is low" do
        monitor.update!(min_severity: "low")
        described_class.perform_now

        expect(SupplyChainChannel).to have_received(:broadcast_cve_alert).with(account, hash_including(severity: "critical"))
      end
    end

    context "with high vulnerabilities" do
      let!(:high_vuln) do
        create(:supply_chain_sbom_vulnerability,
          sbom: sbom,
          component: component,
          account: account,
          severity: "high")
      end

      it "does not create alerts when min_severity is critical" do
        monitor.update!(min_severity: "critical")
        described_class.perform_now

        expect(SupplyChainChannel).not_to have_received(:broadcast_cve_alert)
      end

      it "creates alerts when min_severity is high" do
        monitor.update!(min_severity: "high")
        described_class.perform_now

        expect(SupplyChainChannel).to have_received(:broadcast_cve_alert).with(account, hash_including(severity: "high"))
      end

      it "creates alerts when min_severity is medium" do
        monitor.update!(min_severity: "medium")
        described_class.perform_now

        expect(SupplyChainChannel).to have_received(:broadcast_cve_alert).with(account, hash_including(severity: "high"))
      end

      it "creates alerts when min_severity is low" do
        monitor.update!(min_severity: "low")
        described_class.perform_now

        expect(SupplyChainChannel).to have_received(:broadcast_cve_alert).with(account, hash_including(severity: "high"))
      end
    end

    context "with multiple SBOMs and vulnerabilities" do
      let(:sbom2) { create(:supply_chain_sbom, account: account) }
      let(:component2) { create(:supply_chain_sbom_component, sbom: sbom2, account: account) }
      let!(:critical_vuln) do
        create(:supply_chain_sbom_vulnerability,
          sbom: sbom,
          component: component,
          account: account,
          severity: "critical")
      end
      let!(:high_vuln) do
        create(:supply_chain_sbom_vulnerability,
          sbom: sbom2,
          component: component2,
          account: account,
          severity: "high")
      end

      it "creates alerts for all matching vulnerabilities" do
        monitor.update!(min_severity: "high")
        described_class.perform_now

        expect(SupplyChainChannel).to have_received(:broadcast_cve_alert).twice
      end
    end
  end

  describe "#check_repository_scope" do
    let(:repository) { create(:devops_repository, account: account) }
    let(:other_repository) { create(:devops_repository, account: account) }
    let(:monitor) { create(:supply_chain_cve_monitor, :repository_scope, created_by: user, account: account, scope_id: repository.id, min_severity: "high") }
    let!(:matching_sbom) { create(:supply_chain_sbom, account: account, repository: repository) }
    let!(:non_matching_sbom) { create(:supply_chain_sbom, account: account, repository: other_repository) }
    let!(:component) { create(:supply_chain_sbom_component, sbom: matching_sbom, account: account) }

    context "with valid scope_id" do
      let!(:high_vuln) do
        create(:supply_chain_sbom_vulnerability,
          sbom: matching_sbom,
          component: component,
          account: account,
          severity: "high",
          created_at: 2.hours.ago)
      end

      it "filters SBOMs by repository_id" do
        job = described_class.new
        allow(job).to receive(:check_sboms_for_monitor)

        job.send(:check_repository_scope, monitor)

        expect(job).to have_received(:check_sboms_for_monitor) do |mon, sboms|
          expect(sboms).to include(matching_sbom)
          expect(sboms).not_to include(non_matching_sbom)
        end
      end

      it "calls check_sboms_for_monitor" do
        job = described_class.new
        allow(job).to receive(:check_sboms_for_monitor)

        job.send(:check_repository_scope, monitor)

        expect(job).to have_received(:check_sboms_for_monitor).with(monitor, anything)
      end
    end

    context "without scope_id" do
      let(:monitor) do
        # Build without validation to test edge case handling
        m = build(:supply_chain_cve_monitor, :repository_scope, created_by: user, account: account, scope_id: nil)
        m.save(validate: false)
        m
      end

      it "returns early without processing" do
        job = described_class.new
        allow(job).to receive(:check_sboms_for_monitor)

        job.send(:check_repository_scope, monitor)

        expect(job).not_to have_received(:check_sboms_for_monitor)
      end
    end
  end

  describe "#check_image_scope" do
    let(:image) { create(:supply_chain_container_image, account: account) }
    let(:monitor) { create(:supply_chain_cve_monitor, :image_scope, created_by: user, account: account, scope_id: image.id, min_severity: "critical") }

    context "with valid image and scan data" do
      let!(:scan) do
        create(:supply_chain_vulnerability_scan,
          container_image: image,
          account: account,
          critical_count: 5,
          high_count: 10,
          created_at: 1.hour.ago)
      end

      it "broadcasts alert when critical vulnerabilities found and min_severity is critical" do
        monitor.update!(min_severity: "critical")
        described_class.perform_now

        expect(SupplyChainChannel).to have_received(:broadcast_cve_alert).with(
          account,
          hash_including(
            type: "container_vulnerability",
            severity: "critical",
            image_id: image.id,
            vulnerability_count: 5
          )
        )
      end

      it "broadcasts alert when critical vulnerabilities found and min_severity is high" do
        monitor.update!(min_severity: "high")
        described_class.perform_now

        expect(SupplyChainChannel).to have_received(:broadcast_cve_alert)
      end

      it "broadcasts alert when critical vulnerabilities found and min_severity is medium" do
        monitor.update!(min_severity: "medium")
        described_class.perform_now

        expect(SupplyChainChannel).to have_received(:broadcast_cve_alert)
      end

      it "broadcasts alert when critical vulnerabilities found and min_severity is low" do
        monitor.update!(min_severity: "low")
        described_class.perform_now

        expect(SupplyChainChannel).to have_received(:broadcast_cve_alert)
      end
    end

    context "without critical vulnerabilities" do
      let!(:scan) do
        create(:supply_chain_vulnerability_scan,
          container_image: image,
          account: account,
          critical_count: 0,
          high_count: 10)
      end

      it "does not broadcast alert" do
        described_class.perform_now

        expect(SupplyChainChannel).not_to have_received(:broadcast_cve_alert)
      end
    end

    context "without scope_id" do
      let(:monitor) { create(:supply_chain_cve_monitor, :image_scope, created_by: user, account: account, scope_id: nil) }

      it "returns early without processing" do
        described_class.perform_now

        expect(SupplyChainChannel).not_to have_received(:broadcast_cve_alert)
      end
    end

    context "when image does not exist" do
      let(:monitor) { create(:supply_chain_cve_monitor, :image_scope, created_by: user, account: account, scope_id: SecureRandom.uuid) }

      it "returns early without processing" do
        described_class.perform_now

        expect(SupplyChainChannel).not_to have_received(:broadcast_cve_alert)
      end
    end

    context "when image has no scans" do
      it "returns early without broadcasting" do
        described_class.perform_now

        expect(SupplyChainChannel).not_to have_received(:broadcast_cve_alert)
      end
    end
  end

  describe "#severities_for_min" do
    it "returns only critical for critical min_severity" do
      job = described_class.new
      result = job.send(:severities_for_min, "critical")

      expect(result).to eq(%w[critical])
    end

    it "returns critical and high for high min_severity" do
      job = described_class.new
      result = job.send(:severities_for_min, "high")

      expect(result).to eq(%w[critical high])
    end

    it "returns critical, high, and medium for medium min_severity" do
      job = described_class.new
      result = job.send(:severities_for_min, "medium")

      expect(result).to eq(%w[critical high medium])
    end

    it "returns all severities for low min_severity" do
      job = described_class.new
      result = job.send(:severities_for_min, "low")

      expect(result).to eq(%w[critical high medium low])
    end

    it "returns all severities for unknown min_severity" do
      job = described_class.new
      result = job.send(:severities_for_min, "unknown")

      expect(result).to eq(%w[critical high medium low])
    end
  end

  describe "#create_alert" do
    let(:monitor) { create(:supply_chain_cve_monitor, created_by: user, account: account) }
    let(:sbom) { create(:supply_chain_sbom, account: account) }
    let(:component) { create(:supply_chain_sbom_component, sbom: sbom, account: account, name: "test-package", version: "1.0.0") }
    let(:vuln) do
      create(:supply_chain_sbom_vulnerability,
        sbom: sbom,
        component: component,
        account: account,
        vulnerability_id: "CVE-2024-1234",
        severity: "critical",
        cvss_score: 9.8,
        fixed_version: "1.0.1")
    end

    it "creates alert hash with all required fields" do
      job = described_class.new
      alert = job.send(:create_alert, monitor, sbom, vuln, "critical")

      expect(alert).to include(
        monitor_id: monitor.id,
        vulnerability_id: "CVE-2024-1234",
        severity: "critical",
        cvss_score: 9.8,
        sbom_id: sbom.id,
        sbom_name: sbom.name,
        component: "test-package",
        version: "1.0.0",
        fixed_version: "1.0.1"
      )
    end

    # Note: component_id has NOT NULL constraint in database, so this edge case
    # cannot occur. The create_alert method's safe navigation (component&.name)
    # is defensive coding but won't be exercised in practice.
  end

  describe "#check_sboms_for_monitor" do
    let(:monitor) { create(:supply_chain_cve_monitor, created_by: user, account: account, min_severity: "high", last_run_at: 2.days.ago) }
    let(:sbom) { create(:supply_chain_sbom, account: account) }
    let(:component) { create(:supply_chain_sbom_component, sbom: sbom, account: account) }

    context "with new vulnerabilities since last check" do
      let!(:new_vuln) do
        create(:supply_chain_sbom_vulnerability,
          sbom: sbom,
          component: component,
          account: account,
          severity: "high",
          created_at: 1.hour.ago)
      end

      it "broadcasts alerts for new vulnerabilities" do
        job = described_class.new
        job.send(:check_sboms_for_monitor, monitor, [ sbom ])

        expect(SupplyChainChannel).to have_received(:broadcast_cve_alert).with(account, hash_including(severity: "high"))
      end
    end

    context "with old vulnerabilities" do
      let!(:old_vuln) do
        create(:supply_chain_sbom_vulnerability,
          sbom: sbom,
          component: component,
          account: account,
          severity: "critical",
          created_at: 3.days.ago)
      end

      it "does not broadcast alerts for old vulnerabilities" do
        job = described_class.new
        job.send(:check_sboms_for_monitor, monitor, [ sbom ])

        expect(SupplyChainChannel).not_to have_received(:broadcast_cve_alert)
      end
    end

    context "with vulnerabilities below min_severity" do
      let!(:low_vuln) do
        create(:supply_chain_sbom_vulnerability,
          sbom: sbom,
          component: component,
          account: account,
          severity: "low",
          created_at: 1.hour.ago)
      end

      it "does not broadcast alerts for low severity vulnerabilities" do
        job = described_class.new
        job.send(:check_sboms_for_monitor, monitor, [ sbom ])

        expect(SupplyChainChannel).not_to have_received(:broadcast_cve_alert)
      end
    end

    context "when monitor has no last_run_at" do
      let(:monitor) { create(:supply_chain_cve_monitor, created_by: user, account: account, min_severity: "high", last_run_at: nil) }
      let!(:recent_vuln) do
        create(:supply_chain_sbom_vulnerability,
          sbom: sbom,
          component: component,
          account: account,
          severity: "critical",
          created_at: 12.hours.ago)
      end

      it "checks vulnerabilities from last 1 day" do
        job = described_class.new
        job.send(:check_sboms_for_monitor, monitor, [ sbom ])

        expect(SupplyChainChannel).to have_received(:broadcast_cve_alert)
      end
    end
  end

  describe "logging" do
    context "with account_id" do
      it "logs monitoring start" do
        described_class.perform_now(account.id)

        expect(Rails.logger).to have_received(:info).with("[CveMonitoringJob] Monitoring CVEs for account #{account.id}")
      end

      it "logs CVE count" do
        described_class.perform_now(account.id)

        expect(Rails.logger).to have_received(:info).with(match(/Found \d+ new CVEs for account #{account.id}/))
      end
    end

    context "with monitors" do
      let!(:monitor) { create(:supply_chain_cve_monitor, created_by: user, account: account) }

      it "logs each monitor run" do
        described_class.perform_now

        expect(Rails.logger).to have_received(:info).with("[CveMonitoringJob] Running CVE monitor #{monitor.id}")
      end
    end

    context "with errors" do
      let!(:monitor) { create(:supply_chain_cve_monitor, created_by: user, account: account) }

      before do
        allow_any_instance_of(described_class).to receive(:check_account_wide).and_raise(StandardError.new("Test error"))
      end

      it "logs error with monitor id and message" do
        described_class.perform_now

        expect(Rails.logger).to have_received(:error).with("[CveMonitoringJob] Monitor #{monitor.id} failed: Test error")
      end
    end
  end

  describe "integration test" do
    let!(:monitor) { create(:supply_chain_cve_monitor, :critical_only, account: account, created_by: user) }
    let!(:sbom) { create(:supply_chain_sbom, account: account) }
    let!(:component) { create(:supply_chain_sbom_component, sbom: sbom, account: account) }
    let!(:critical_vuln) do
      create(:supply_chain_sbom_vulnerability,
        sbom: sbom,
        component: component,
        account: account,
        severity: "critical",
        created_at: 2.hours.ago)
    end

    it "successfully completes full workflow" do
      freeze_time do
        described_class.perform_now

        expect(Rails.logger).to have_received(:info).with("[CveMonitoringJob] Running CVE monitor #{monitor.id}")
        expect(SupplyChainChannel).to have_received(:broadcast_cve_alert).with(account, hash_including(severity: "critical"))
        expect(monitor.reload.last_run_at).to be_within(1.second).of(Time.current)
      end
    end
  end

  describe "enqueuing" do
    it "enqueues the job on the correct queue" do
      expect {
        described_class.perform_later(account.id)
      }.to have_enqueued_job(described_class).with(account.id).on_queue("supply_chain_monitoring")
    end

    it "enqueues without arguments" do
      expect {
        described_class.perform_later
      }.to have_enqueued_job(described_class).with(no_args).on_queue("supply_chain_monitoring")
    end
  end
end
