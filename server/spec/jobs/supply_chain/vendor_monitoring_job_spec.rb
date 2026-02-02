# frozen_string_literal: true

require "rails_helper"

RSpec.describe SupplyChain::VendorMonitoringJob, type: :job do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:vendor) { create(:supply_chain_vendor, account: account, status: "active", next_assessment_due: nil) }

  describe "queue" do
    it "uses supply_chain_monitoring queue" do
      expect(described_class.new.queue_name).to eq("supply_chain_monitoring")
    end
  end

  describe "#perform" do
    let(:risk_service) { instance_double(SupplyChain::VendorRiskService) }
    let(:monitoring_events) { [] }

    before do
      allow(SupplyChain::VendorRiskService).to receive(:new).and_return(risk_service)
      allow(risk_service).to receive(:monitor_vendor!).and_return(monitoring_events)
      allow(SupplyChainChannel).to receive(:broadcast_vendor_monitoring_event)
    end

    context "with account_id parameter" do
      before { vendor } # Ensure vendor is created before job runs

      it "finds the account by ID" do
        described_class.perform_now(account.id)
        expect(SupplyChain::VendorRiskService).to have_received(:new).with(account: vendor.account, vendor: vendor)
      end

      it "raises error when account is not found" do
        expect {
          described_class.perform_now("non-existent-id")
        }.to raise_error(ActiveRecord::RecordNotFound)
      end

      it "monitors only vendors for the specified account" do
        other_account = create(:account)
        other_vendor = create(:supply_chain_vendor, account: other_account, status: "active", next_assessment_due: nil)

        described_class.perform_now(account.id)

        expect(SupplyChain::VendorRiskService).to have_received(:new).with(account: vendor.account, vendor: vendor)
        expect(SupplyChain::VendorRiskService).not_to have_received(:new).with(account: other_vendor.account, vendor: other_vendor)
      end

      it "only monitors active vendors" do
        inactive_vendor = create(:supply_chain_vendor, account: account, status: "inactive", next_assessment_due: nil)

        described_class.perform_now(account.id)

        expect(SupplyChain::VendorRiskService).to have_received(:new).with(account: vendor.account, vendor: vendor).once
        expect(SupplyChain::VendorRiskService).not_to have_received(:new).with(account: inactive_vendor.account, vendor: inactive_vendor)
      end
    end

    context "without account_id parameter" do
      let(:account2) { create(:account) }
      let(:vendor2) { create(:supply_chain_vendor, account: account2, status: "active", next_assessment_due: nil) }

      before do
        vendor # Ensure vendor is created
        vendor2 # Ensure vendor2 is created
      end

      it "monitors all accounts with active vendors" do
        described_class.perform_now

        expect(SupplyChain::VendorRiskService).to have_received(:new).with(account: vendor.account, vendor: vendor)
        expect(SupplyChain::VendorRiskService).to have_received(:new).with(account: vendor2.account, vendor: vendor2)
      end

      it "only monitors active vendors across all accounts" do
        inactive_vendor = create(:supply_chain_vendor, account: account, status: "inactive", next_assessment_due: nil)

        described_class.perform_now

        expect(SupplyChain::VendorRiskService).to have_received(:new).with(account: vendor.account, vendor: vendor)
        expect(SupplyChain::VendorRiskService).not_to have_received(:new).with(account: inactive_vendor.account, vendor: inactive_vendor)
      end

      it "does not monitor accounts with no active vendors" do
        account_without_vendors = create(:account)

        described_class.perform_now

        expect(SupplyChain::VendorRiskService).to have_received(:new).with(account: vendor.account, vendor: vendor)
        expect(SupplyChain::VendorRiskService).not_to have_received(:new).with(hash_including(account: account_without_vendors))
      end

      it "processes accounts distinctly even with multiple vendors" do
        vendor2_same_account = create(:supply_chain_vendor, account: account, status: "active", next_assessment_due: nil)

        described_class.perform_now

        expect(SupplyChain::VendorRiskService).to have_received(:new).with(account: vendor.account, vendor: vendor)
        expect(SupplyChain::VendorRiskService).to have_received(:new).with(account: vendor2_same_account.account, vendor: vendor2_same_account)
      end
    end

    context "when monitoring account vendors" do
      before { vendor } # Ensure vendor is created before job runs

      it "iterates through all active vendors" do
        vendor2 = create(:supply_chain_vendor, account: account, status: "active", next_assessment_due: nil)

        described_class.perform_now(account.id)

        expect(SupplyChain::VendorRiskService).to have_received(:new).with(account: vendor.account, vendor: vendor)
        expect(SupplyChain::VendorRiskService).to have_received(:new).with(account: vendor2.account, vendor: vendor2)
      end

      it "handles vendor errors gracefully and continues processing" do
        vendor2 = create(:supply_chain_vendor, account: account, status: "active", next_assessment_due: nil)

        allow(SupplyChain::VendorRiskService).to receive(:new).with(account: vendor.account, vendor: vendor).and_raise(StandardError.new("Service error"))
        allow(SupplyChain::VendorRiskService).to receive(:new).with(account: vendor2.account, vendor: vendor2).and_return(risk_service)
        allow(Rails.logger).to receive(:error)

        described_class.perform_now(account.id)

        expect(Rails.logger).to have_received(:error).with("[VendorMonitoringJob] Failed to monitor vendor #{vendor.id}: Service error")
        expect(SupplyChain::VendorRiskService).to have_received(:new).with(account: vendor2.account, vendor: vendor2)
      end

      it "logs an error for each vendor that fails" do
        allow(SupplyChain::VendorRiskService).to receive(:new).and_raise(StandardError.new("Connection timeout"))
        allow(Rails.logger).to receive(:error)

        described_class.perform_now(account.id)

        expect(Rails.logger).to have_received(:error).with("[VendorMonitoringJob] Failed to monitor vendor #{vendor.id}: Connection timeout")
      end
    end

    context "when monitoring a vendor" do
      before do
        # Ensure vendor is created before job runs
        # Set next_assessment_due to future to prevent check_assessment_due from creating events
        vendor.update!(next_assessment_due: 30.days.from_now)
      end

      it "calls VendorRiskService.monitor_vendor!" do
        described_class.perform_now(account.id)

        expect(risk_service).to have_received(:monitor_vendor!)
      end

      it "creates VendorRiskService with correct account and vendor" do
        described_class.perform_now(account.id)

        expect(SupplyChain::VendorRiskService).to have_received(:new).with(account: vendor.account, vendor: vendor)
      end

      it "broadcasts events returned from monitor_vendor!" do
        event1 = create(:supply_chain_vendor_monitoring_event, vendor: vendor, account: account)
        event2 = create(:supply_chain_vendor_monitoring_event, vendor: vendor, account: account)
        allow(risk_service).to receive(:monitor_vendor!).and_return([ event1, event2 ])

        described_class.perform_now(account.id)

        expect(SupplyChainChannel).to have_received(:broadcast_vendor_monitoring_event).with(event1)
        expect(SupplyChainChannel).to have_received(:broadcast_vendor_monitoring_event).with(event2)
      end

      it "broadcasts no events when monitor_vendor! returns empty array" do
        allow(risk_service).to receive(:monitor_vendor!).and_return([])

        described_class.perform_now(account.id)

        expect(SupplyChainChannel).not_to have_received(:broadcast_vendor_monitoring_event)
      end
    end

    context "when checking assessment due" do
      context "when vendor needs assessment" do
        before do
          vendor.update!(next_assessment_due: 1.day.ago)
        end

        it "creates compliance_update event when needed" do
          expect {
            described_class.perform_now(account.id)
          }.to change { SupplyChain::VendorMonitoringEvent.where(event_type: "compliance_update").count }.by(1)
        end

        it "sets correct attributes on created event" do
          described_class.perform_now(account.id)

          event = SupplyChain::VendorMonitoringEvent.last
          expect(event.vendor).to eq(vendor)
          expect(event.account).to eq(account)
          expect(event.event_type).to eq("compliance_update")
          expect(event.severity).to eq("medium")
          expect(event.source).to eq("automated")
          expect(event.title).to eq("Risk assessment overdue")
          expect(event.description).to eq("Vendor #{vendor.name} requires a new risk assessment")
        end

        it "includes recommended actions in created event" do
          described_class.perform_now(account.id)

          event = SupplyChain::VendorMonitoringEvent.last
          expect(event.recommended_actions).to be_an(Array)
          expect(event.recommended_actions.first["action"]).to eq("Schedule and complete vendor risk assessment")
          expect(event.recommended_actions.first["priority"]).to eq("high")
          expect(event.recommended_actions.first["status"]).to eq("pending")
        end

        it "broadcasts the created event" do
          described_class.perform_now(account.id)

          event = SupplyChain::VendorMonitoringEvent.last
          expect(SupplyChainChannel).to have_received(:broadcast_vendor_monitoring_event).with(event)
        end

        context "when recent compliance_update event exists" do
          before do
            create(:supply_chain_vendor_monitoring_event,
              vendor: vendor,
              account: account,
              event_type: "compliance_update",
              created_at: 5.days.ago)
          end

          it "does not create a new event" do
            expect {
              described_class.perform_now(account.id)
            }.not_to change { SupplyChain::VendorMonitoringEvent.where(event_type: "compliance_update").count }
          end
        end

        context "when old compliance_update event exists" do
          before do
            create(:supply_chain_vendor_monitoring_event,
              vendor: vendor,
              account: account,
              event_type: "compliance_update",
              created_at: 10.days.ago)
          end

          it "creates a new event" do
            expect {
              described_class.perform_now(account.id)
            }.to change { SupplyChain::VendorMonitoringEvent.where(event_type: "compliance_update").count }.by(1)
          end
        end
      end

      context "when vendor does not need assessment" do
        before do
          vendor.update!(next_assessment_due: 30.days.from_now)
        end

        it "does not create an event" do
          expect {
            described_class.perform_now(account.id)
          }.not_to change { SupplyChain::VendorMonitoringEvent.where(event_type: "compliance_update").count }
        end
      end
    end

    context "when checking contract expiry" do
      context "with no contract_end_date" do
        before do
          vendor.update!(contract_end_date: nil)
        end

        it "does not create an event" do
          expect {
            described_class.perform_now(account.id)
          }.not_to change { SupplyChain::VendorMonitoringEvent.where(event_type: "contract_renewal").count }
        end
      end

      context "with contract_end_date in the future (beyond 60 days)" do
        before do
          vendor.update!(contract_end_date: 90.days.from_now.to_date)
        end

        it "does not create an event" do
          expect {
            described_class.perform_now(account.id)
          }.not_to change { SupplyChain::VendorMonitoringEvent.where(event_type: "contract_renewal").count }
        end
      end

      context "with contract_end_date in the past" do
        before do
          vendor.update!(contract_end_date: 5.days.ago.to_date)
        end

        it "does not create an event" do
          expect {
            described_class.perform_now(account.id)
          }.not_to change { SupplyChain::VendorMonitoringEvent.where(event_type: "contract_renewal").count }
        end
      end

      context "with contract expiring within 60 days" do
        before do
          vendor.update!(contract_end_date: 30.days.from_now.to_date)
        end

        it "creates contract_renewal event" do
          expect {
            described_class.perform_now(account.id)
          }.to change { SupplyChain::VendorMonitoringEvent.where(event_type: "contract_renewal").count }.by(1)
        end

        it "sets correct attributes on created event" do
          described_class.perform_now(account.id)

          event = SupplyChain::VendorMonitoringEvent.where(event_type: "contract_renewal").last
          expect(event.vendor).to eq(vendor)
          expect(event.account).to eq(account)
          expect(event.source).to eq("automated")
          expect(event.title).to eq("Contract expiring soon")
        end

        it "includes contract details in description" do
          described_class.perform_now(account.id)

          event = SupplyChain::VendorMonitoringEvent.where(event_type: "contract_renewal").last
          expect(event.description).to include(vendor.name)
          expect(event.description).to include(vendor.contract_end_date.to_s)
        end

        it "includes metadata with contract information" do
          described_class.perform_now(account.id)

          event = SupplyChain::VendorMonitoringEvent.where(event_type: "contract_renewal").last
          expect(event.metadata["contract_end_date"]).to eq(vendor.contract_end_date.iso8601)
          expect(event.metadata["days_until_expiry"]).to be_within(1).of(30)
        end

        it "includes recommended actions" do
          described_class.perform_now(account.id)

          event = SupplyChain::VendorMonitoringEvent.where(event_type: "contract_renewal").last
          expect(event.recommended_actions).to be_an(Array)
          expect(event.recommended_actions.first["action"]).to eq("Review and renew vendor contract")
          expect(event.recommended_actions.first["status"]).to eq("pending")
        end

        it "broadcasts the created event" do
          described_class.perform_now(account.id)

          event = SupplyChain::VendorMonitoringEvent.where(event_type: "contract_renewal").last
          expect(SupplyChainChannel).to have_received(:broadcast_vendor_monitoring_event).with(event)
        end

        context "when recent contract_renewal event exists" do
          before do
            create(:supply_chain_vendor_monitoring_event,
              vendor: vendor,
              account: account,
              event_type: "contract_renewal",
              created_at: 10.days.ago)
          end

          it "does not create a new event" do
            expect {
              described_class.perform_now(account.id)
            }.not_to change { SupplyChain::VendorMonitoringEvent.where(event_type: "contract_renewal").count }
          end
        end

        context "when old contract_renewal event exists" do
          before do
            create(:supply_chain_vendor_monitoring_event,
              vendor: vendor,
              account: account,
              event_type: "contract_renewal",
              created_at: 20.days.ago)
          end

          it "creates a new event" do
            expect {
              described_class.perform_now(account.id)
            }.to change { SupplyChain::VendorMonitoringEvent.where(event_type: "contract_renewal").count }.by(1)
          end
        end
      end

      context "severity based on days until expiry" do
        it "sets high severity when expiring within 14 days" do
          vendor.update!(contract_end_date: 10.days.from_now.to_date)

          described_class.perform_now(account.id)

          event = SupplyChain::VendorMonitoringEvent.where(event_type: "contract_renewal").last
          expect(event.severity).to eq("high")
          expect(event.recommended_actions.first["priority"]).to eq("high")
        end

        it "sets medium severity when expiring within 15-30 days" do
          vendor.update!(contract_end_date: 20.days.from_now.to_date)

          described_class.perform_now(account.id)

          event = SupplyChain::VendorMonitoringEvent.where(event_type: "contract_renewal").last
          expect(event.severity).to eq("medium")
          expect(event.recommended_actions.first["priority"]).to eq("medium")
        end

        it "sets low severity when expiring within 31-60 days" do
          vendor.update!(contract_end_date: 45.days.from_now.to_date)

          described_class.perform_now(account.id)

          event = SupplyChain::VendorMonitoringEvent.where(event_type: "contract_renewal").last
          expect(event.severity).to eq("low")
          expect(event.recommended_actions.first["priority"]).to eq("low")
        end

        it "sets high severity when expiring on the exact day (0 days)" do
          vendor.update!(contract_end_date: Date.current)

          described_class.perform_now(account.id)

          event = SupplyChain::VendorMonitoringEvent.where(event_type: "contract_renewal").last
          expect(event.severity).to eq("high")
        end

        it "sets high severity when expiring exactly in 14 days" do
          vendor.update!(contract_end_date: 14.days.from_now.to_date)

          described_class.perform_now(account.id)

          event = SupplyChain::VendorMonitoringEvent.where(event_type: "contract_renewal").last
          expect(event.severity).to eq("high")
        end

        it "sets medium severity when expiring exactly in 30 days" do
          vendor.update!(contract_end_date: 30.days.from_now.to_date)

          described_class.perform_now(account.id)

          event = SupplyChain::VendorMonitoringEvent.where(event_type: "contract_renewal").last
          expect(event.severity).to eq("medium")
        end

        it "sets low severity when expiring exactly in 60 days" do
          vendor.update!(contract_end_date: 60.days.from_now.to_date)

          described_class.perform_now(account.id)

          event = SupplyChain::VendorMonitoringEvent.where(event_type: "contract_renewal").last
          expect(event.severity).to eq("low")
        end
      end
    end

    context "when checking certification expiry" do
      context "with no certifications" do
        before do
          vendor.update!(certifications: nil)
        end

        it "does not create an event" do
          expect {
            described_class.perform_now(account.id)
          }.not_to change { SupplyChain::VendorMonitoringEvent.where(event_type: "certification_expiry").count }
        end
      end

      context "with empty certifications array" do
        before do
          vendor.update!(certifications: [])
        end

        it "does not create an event" do
          expect {
            described_class.perform_now(account.id)
          }.not_to change { SupplyChain::VendorMonitoringEvent.where(event_type: "certification_expiry").count }
        end
      end

      context "with certification without expires_at" do
        before do
          vendor.update!(certifications: [
            { "name" => "ISO27001", "issued_at" => 1.year.ago.iso8601 }
          ])
        end

        it "does not create an event" do
          expect {
            described_class.perform_now(account.id)
          }.not_to change { SupplyChain::VendorMonitoringEvent.where(event_type: "certification_expiry").count }
        end
      end

      context "with certification expiring beyond 30 days" do
        before do
          vendor.update!(certifications: [
            { "name" => "ISO27001", "expires_at" => 45.days.from_now.iso8601 }
          ])
        end

        it "does not create an event" do
          expect {
            described_class.perform_now(account.id)
          }.not_to change { SupplyChain::VendorMonitoringEvent.where(event_type: "certification_expiry").count }
        end
      end

      context "with certification already expired" do
        before do
          vendor.update!(certifications: [
            { "name" => "ISO27001", "expires_at" => 5.days.ago.iso8601 }
          ])
        end

        it "does not create an event" do
          expect {
            described_class.perform_now(account.id)
          }.not_to change { SupplyChain::VendorMonitoringEvent.where(event_type: "certification_expiry").count }
        end
      end

      context "with certification expiring within 30 days" do
        before do
          vendor.update!(certifications: [
            { "name" => "ISO27001", "expires_at" => 15.days.from_now.iso8601 }
          ])
        end

        it "creates certification_expiry event" do
          expect {
            described_class.perform_now(account.id)
          }.to change { SupplyChain::VendorMonitoringEvent.where(event_type: "certification_expiry").count }.by(1)
        end

        it "sets correct attributes on created event" do
          described_class.perform_now(account.id)

          event = SupplyChain::VendorMonitoringEvent.where(event_type: "certification_expiry").last
          expect(event.vendor).to eq(vendor)
          expect(event.account).to eq(account)
          expect(event.source).to eq("automated")
          expect(event.title).to eq("Certification expiring: ISO27001")
        end

        it "includes certification details in description" do
          described_class.perform_now(account.id)

          event = SupplyChain::VendorMonitoringEvent.where(event_type: "certification_expiry").last
          expect(event.description).to include(vendor.name)
          expect(event.description).to include("ISO27001")
        end

        it "includes metadata with certification information" do
          described_class.perform_now(account.id)

          event = SupplyChain::VendorMonitoringEvent.where(event_type: "certification_expiry").last
          expect(event.metadata["certification_name"]).to eq("ISO27001")
          expect(event.metadata["days_until_expiry"]).to be_within(1).of(15)
        end

        it "includes recommended actions" do
          described_class.perform_now(account.id)

          event = SupplyChain::VendorMonitoringEvent.where(event_type: "certification_expiry").last
          expect(event.recommended_actions).to be_an(Array)
          expect(event.recommended_actions.first["action"]).to eq("Request updated certification from vendor")
          expect(event.recommended_actions.first["status"]).to eq("pending")
        end

        it "broadcasts the created event" do
          described_class.perform_now(account.id)

          event = SupplyChain::VendorMonitoringEvent.where(event_type: "certification_expiry").last
          expect(SupplyChainChannel).to have_received(:broadcast_vendor_monitoring_event).with(event)
        end

        context "when recent certification_expiry event exists for same certification" do
          before do
            create(:supply_chain_vendor_monitoring_event,
              vendor: vendor,
              account: account,
              event_type: "certification_expiry",
              metadata: { "certification_name" => "ISO27001" },
              created_at: 10.days.ago)
          end

          it "does not create a new event" do
            expect {
              described_class.perform_now(account.id)
            }.not_to change { SupplyChain::VendorMonitoringEvent.where(event_type: "certification_expiry").count }
          end
        end

        context "when old certification_expiry event exists for same certification" do
          before do
            create(:supply_chain_vendor_monitoring_event,
              vendor: vendor,
              account: account,
              event_type: "certification_expiry",
              metadata: { "certification_name" => "ISO27001" },
              created_at: 20.days.ago)
          end

          it "creates a new event" do
            expect {
              described_class.perform_now(account.id)
            }.to change { SupplyChain::VendorMonitoringEvent.where(event_type: "certification_expiry").count }.by(1)
          end
        end

        context "when recent event exists for different certification" do
          before do
            create(:supply_chain_vendor_monitoring_event,
              vendor: vendor,
              account: account,
              event_type: "certification_expiry",
              metadata: { "certification_name" => "SOC2" },
              created_at: 10.days.ago)
          end

          it "creates a new event for the different certification" do
            expect {
              described_class.perform_now(account.id)
            }.to change { SupplyChain::VendorMonitoringEvent.where(event_type: "certification_expiry").count }.by(1)
          end
        end
      end

      context "with multiple certifications expiring" do
        before do
          vendor.update!(certifications: [
            { "name" => "ISO27001", "expires_at" => 15.days.from_now.iso8601 },
            { "name" => "SOC2", "expires_at" => 25.days.from_now.iso8601 },
            { "name" => "HIPAA", "expires_at" => 5.days.from_now.iso8601 }
          ])
        end

        it "creates an event for each expiring certification" do
          expect {
            described_class.perform_now(account.id)
          }.to change { SupplyChain::VendorMonitoringEvent.where(event_type: "certification_expiry").count }.by(3)
        end

        it "creates events with correct certification names" do
          described_class.perform_now(account.id)

          events = SupplyChain::VendorMonitoringEvent.where(event_type: "certification_expiry").order(:created_at)
          expect(events.map { |e| e.metadata["certification_name"] }).to contain_exactly("ISO27001", "SOC2", "HIPAA")
        end
      end

      context "with mixed certifications (some expiring, some not)" do
        before do
          vendor.update!(certifications: [
            { "name" => "ISO27001", "expires_at" => 15.days.from_now.iso8601 },
            { "name" => "SOC2", "expires_at" => 45.days.from_now.iso8601 },
            { "name" => "PCI-DSS", "expires_at" => 5.days.ago.iso8601 }
          ])
        end

        it "only creates events for certifications expiring within 30 days" do
          expect {
            described_class.perform_now(account.id)
          }.to change { SupplyChain::VendorMonitoringEvent.where(event_type: "certification_expiry").count }.by(1)

          event = SupplyChain::VendorMonitoringEvent.where(event_type: "certification_expiry").last
          expect(event.metadata["certification_name"]).to eq("ISO27001")
        end
      end

      context "severity based on days until expiry" do
        it "sets high severity when expiring within 7 days" do
          vendor.update!(certifications: [
            { "name" => "ISO27001", "expires_at" => 5.days.from_now.iso8601 }
          ])

          described_class.perform_now(account.id)

          event = SupplyChain::VendorMonitoringEvent.where(event_type: "certification_expiry").last
          expect(event.severity).to eq("high")
          expect(event.recommended_actions.first["priority"]).to eq("high")
        end

        it "sets medium severity when expiring within 8-30 days" do
          vendor.update!(certifications: [
            { "name" => "ISO27001", "expires_at" => 20.days.from_now.iso8601 }
          ])

          described_class.perform_now(account.id)

          event = SupplyChain::VendorMonitoringEvent.where(event_type: "certification_expiry").last
          expect(event.severity).to eq("medium")
          expect(event.recommended_actions.first["priority"]).to eq("medium")
        end

        it "sets high severity when expiring exactly in 7 days" do
          vendor.update!(certifications: [
            { "name" => "ISO27001", "expires_at" => 7.days.from_now.iso8601 }
          ])

          described_class.perform_now(account.id)

          event = SupplyChain::VendorMonitoringEvent.where(event_type: "certification_expiry").last
          expect(event.severity).to eq("high")
        end

        it "sets high severity when expiring on the exact day (0 days)" do
          vendor.update!(certifications: [
            { "name" => "ISO27001", "expires_at" => Time.current.iso8601 }
          ])

          described_class.perform_now(account.id)

          event = SupplyChain::VendorMonitoringEvent.where(event_type: "certification_expiry").last
          expect(event.severity).to eq("high")
        end
      end
    end

    context "when logging" do
      before { vendor } # Ensure vendor is created before job runs

      it "logs the start of monitoring for each account" do
        allow(Rails.logger).to receive(:info)

        described_class.perform_now(account.id)

        expect(Rails.logger).to have_received(:info).with("[VendorMonitoringJob] Monitoring vendors for account #{account.id}")
      end

      it "logs errors when vendor monitoring fails" do
        allow(SupplyChain::VendorRiskService).to receive(:new).and_raise(StandardError.new("Connection error"))
        allow(Rails.logger).to receive(:info)
        allow(Rails.logger).to receive(:error)

        described_class.perform_now(account.id)

        expect(Rails.logger).to have_received(:error).with("[VendorMonitoringJob] Failed to monitor vendor #{vendor.id}: Connection error")
      end
    end

    context "with integration test" do
      before do
        vendor # Ensure vendor is created first
        allow(SupplyChain::VendorRiskService).to receive(:new).and_call_original
        allow(SupplyChainChannel).to receive(:broadcast_vendor_monitoring_event)
      end

      it "executes the full job workflow for a specific account" do
        vendor.update!(
          next_assessment_due: 1.day.ago,
          contract_end_date: 30.days.from_now.to_date,
          certifications: [ { "name" => "ISO27001", "expires_at" => 15.days.from_now.iso8601 } ]
        )

        expect {
          described_class.perform_now(account.id)
        }.to change { SupplyChain::VendorMonitoringEvent.count }

        expect(SupplyChainChannel).to have_received(:broadcast_vendor_monitoring_event).at_least(:once)
      end

      it "executes the full job workflow for all accounts" do
        account2 = create(:account)
        vendor2 = create(:supply_chain_vendor, account: account2, status: "active", next_assessment_due: nil)

        vendor.update!(contract_end_date: 30.days.from_now.to_date)
        vendor2.update!(contract_end_date: 20.days.from_now.to_date)

        expect {
          described_class.perform_now
        }.to change { SupplyChain::VendorMonitoringEvent.count }

        expect(SupplyChainChannel).to have_received(:broadcast_vendor_monitoring_event).at_least(:once)
      end
    end

    context "with enqueuing" do
      before { vendor } # Ensure vendor is created before job runs

      it "enqueues the job with account_id" do
        expect {
          described_class.perform_later(account.id)
        }.to have_enqueued_job(described_class).with(account.id).on_queue("supply_chain_monitoring")
      end

      it "enqueues the job without account_id" do
        expect {
          described_class.perform_later
        }.to have_enqueued_job(described_class).with(no_args).on_queue("supply_chain_monitoring")
      end

      it "performs enqueued jobs" do
        perform_enqueued_jobs do
          described_class.perform_later(account.id)
        end

        expect(SupplyChain::VendorRiskService).to have_received(:new).with(account: vendor.account, vendor: vendor)
      end
    end
  end
end
