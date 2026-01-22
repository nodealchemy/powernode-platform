# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::SupplyChain::BaseController do
  let(:account) { create(:account) }
  let(:user_with_read) { create(:user, account: account, permissions: ['supply_chain.read']) }
  let(:user_with_write) { create(:user, account: account, permissions: ['supply_chain.read', 'supply_chain.write']) }
  let(:user_with_admin) { create(:user, account: account, permissions: ['supply_chain.read', 'supply_chain.write', 'supply_chain.admin']) }
  let(:user_without_permissions) { create(:user, account: account, permissions: []) }

  # Create a simple instance for testing private methods
  let(:controller_instance) do
    controller = described_class.new
    allow(controller).to receive(:current_user).and_return(current_user)
    controller
  end

  describe 'class structure' do
    it 'inherits from ApplicationController' do
      expect(described_class.superclass).to eq(ApplicationController)
    end

    it 'includes AuditLogging concern' do
      expect(described_class.ancestors.map(&:to_s)).to include('AuditLogging')
    end

    it 'includes Paginatable concern' do
      expect(described_class.ancestors.map(&:to_s)).to include('Paginatable')
    end

    it 'has before_action :authenticate_request' do
      callbacks = described_class._process_action_callbacks
      auth_callback = callbacks.find { |cb| cb.filter == :authenticate_request }
      expect(auth_callback).to be_present
      expect(auth_callback.kind).to eq(:before)
    end
  end

  describe 'permission methods' do
    describe '#require_read_permission' do
      context 'when user has supply_chain.read permission' do
        let(:current_user) { user_with_read }

        it 'allows access and does not render error' do
          expect(controller_instance).not_to receive(:render_error)
          controller_instance.send(:require_read_permission)
        end
      end

      context 'when user does not have supply_chain.read permission' do
        let(:current_user) { user_without_permissions }

        it 'renders forbidden error' do
          expect(controller_instance).to receive(:render_error).with(
            'Insufficient permissions to view supply chain data',
            status: :forbidden
          )
          controller_instance.send(:require_read_permission)
        end
      end

      context 'when user has write permission (includes read)' do
        let(:current_user) { user_with_write }

        it 'allows access' do
          expect(controller_instance).not_to receive(:render_error)
          controller_instance.send(:require_read_permission)
        end
      end

      context 'when user has admin permission (includes read)' do
        let(:current_user) { user_with_admin }

        it 'allows access' do
          expect(controller_instance).not_to receive(:render_error)
          controller_instance.send(:require_read_permission)
        end
      end
    end

    describe '#require_write_permission' do
      context 'when user has supply_chain.write permission' do
        let(:current_user) { user_with_write }

        it 'allows access and does not render error' do
          expect(controller_instance).not_to receive(:render_error)
          controller_instance.send(:require_write_permission)
        end
      end

      context 'when user does not have supply_chain.write permission' do
        let(:current_user) { user_with_read }

        it 'renders forbidden error' do
          expect(controller_instance).to receive(:render_error).with(
            'Insufficient permissions to manage supply chain data',
            status: :forbidden
          )
          controller_instance.send(:require_write_permission)
        end
      end

      context 'when user has admin permission (includes write)' do
        let(:current_user) { user_with_admin }

        it 'allows access' do
          expect(controller_instance).not_to receive(:render_error)
          controller_instance.send(:require_write_permission)
        end
      end

      context 'when user has no permissions' do
        let(:current_user) { user_without_permissions }

        it 'renders forbidden error' do
          expect(controller_instance).to receive(:render_error).with(
            'Insufficient permissions to manage supply chain data',
            status: :forbidden
          )
          controller_instance.send(:require_write_permission)
        end
      end
    end

    describe '#require_admin_permission' do
      context 'when user has supply_chain.admin permission' do
        let(:current_user) { user_with_admin }

        it 'allows access and does not render error' do
          expect(controller_instance).not_to receive(:render_error)
          controller_instance.send(:require_admin_permission)
        end
      end

      context 'when user has only write permission' do
        let(:current_user) { user_with_write }

        it 'renders forbidden error' do
          expect(controller_instance).to receive(:render_error).with(
            'Insufficient permissions for supply chain administration',
            status: :forbidden
          )
          controller_instance.send(:require_admin_permission)
        end
      end

      context 'when user has only read permission' do
        let(:current_user) { user_with_read }

        it 'renders forbidden error' do
          expect(controller_instance).to receive(:render_error).with(
            'Insufficient permissions for supply chain administration',
            status: :forbidden
          )
          controller_instance.send(:require_admin_permission)
        end
      end

      context 'when user has no permissions' do
        let(:current_user) { user_without_permissions }

        it 'renders forbidden error' do
          expect(controller_instance).to receive(:render_error).with(
            'Insufficient permissions for supply chain administration',
            status: :forbidden
          )
          controller_instance.send(:require_admin_permission)
        end
      end
    end
  end

  describe '#current_account' do
    let(:current_user) { user_with_read }

    it 'returns the current user account' do
      result = controller_instance.send(:current_account)

      expect(result).to eq(account)
      expect(result.id).to eq(account.id)
    end

    it 'memoizes the account' do
      # Call multiple times to test memoization
      first_result = controller_instance.send(:current_account)
      second_result = controller_instance.send(:current_account)

      expect(first_result.object_id).to eq(second_result.object_id)
    end
  end

  describe 'serializer methods' do
    let(:current_user) { user_with_read }

    describe '#serialize_sbom' do
      let!(:sbom) { create(:supply_chain_sbom, account: account, repository: nil) }

      it 'returns serialized sbom data with all required fields' do
        result = controller_instance.send(:serialize_sbom, sbom)

        expect(result[:id]).to eq(sbom.id)
        expect(result[:sbom_id]).to eq(sbom.sbom_id)
        expect(result[:name]).to eq(sbom.name)
        expect(result[:version]).to eq(sbom.version)
        expect(result[:format]).to eq(sbom.format)
        expect(result[:component_count]).to eq(sbom.component_count)
        expect(result[:vulnerability_count]).to eq(sbom.vulnerability_count)
        expect(result[:risk_score]).to eq(sbom.risk_score)
        expect(result[:ntia_minimum_compliant]).to eq(sbom.ntia_minimum_compliant)
        expect(result[:status]).to eq(sbom.status)
        expect(result[:created_at]).to be_present
        expect(result[:updated_at]).to be_present
      end

      it 'does not include repository by default' do
        result = controller_instance.send(:serialize_sbom, sbom)

        expect(result).not_to have_key(:repository)
      end

      context 'when sbom has no repository' do
        it 'does not include repository data even when requested' do
          result = controller_instance.send(:serialize_sbom, sbom, include_repository: true)

          expect(result).not_to have_key(:repository)
        end
      end
    end

    describe '#serialize_attestation' do
      let!(:attestation) { create(:supply_chain_attestation, :signed, :verified, :logged_to_rekor, account: account) }

      it 'returns serialized attestation data' do
        result = controller_instance.send(:serialize_attestation, attestation)

        expect(result[:id]).to eq(attestation.id)
        expect(result[:attestation_id]).to eq(attestation.attestation_id)
        expect(result[:attestation_type]).to eq(attestation.attestation_type)
        expect(result[:slsa_level]).to eq(attestation.slsa_level)
        expect(result[:subject_name]).to eq(attestation.subject_name)
        expect(result[:subject_digest]).to eq(attestation.subject_digest)
        expect(result[:signed]).to be true
        expect(result[:verified]).to be true
        expect(result[:rekor_logged]).to be true
        expect(result[:created_at]).to be_present
      end

      context 'when attestation is not signed' do
        let!(:unsigned_attestation) { create(:supply_chain_attestation, account: account) }

        it 'returns signed as false' do
          result = controller_instance.send(:serialize_attestation, unsigned_attestation)

          expect(result[:signed]).to be false
          expect(result[:verified]).to be false
          expect(result[:rekor_logged]).to be false
        end
      end
    end

    describe '#serialize_container_image' do
      let!(:image) { create(:supply_chain_container_image, account: account) }

      it 'returns serialized container image data' do
        result = controller_instance.send(:serialize_container_image, image)

        expect(result[:id]).to eq(image.id)
        expect(result[:registry]).to eq(image.registry)
        expect(result[:repository]).to eq(image.repository)
        expect(result[:tag]).to eq(image.tag)
        expect(result[:digest]).to eq(image.digest)
        expect(result[:status]).to eq(image.status)
        expect(result[:critical_vuln_count]).to eq(image.critical_vuln_count)
        expect(result[:high_vuln_count]).to eq(image.high_vuln_count)
        expect(result[:medium_vuln_count]).to eq(image.medium_vuln_count)
        expect(result[:low_vuln_count]).to eq(image.low_vuln_count)
        expect(result[:is_deployed]).to eq(image.is_deployed)
        expect(result[:created_at]).to be_present
      end

      context 'with high vulnerability counts' do
        let!(:vulnerable_image) do
          create(:supply_chain_container_image,
                 account: account,
                 critical_vuln_count: 5,
                 high_vuln_count: 15,
                 medium_vuln_count: 30,
                 low_vuln_count: 50)
        end

        it 'includes accurate vulnerability counts' do
          result = controller_instance.send(:serialize_container_image, vulnerable_image)

          expect(result[:critical_vuln_count]).to eq(5)
          expect(result[:high_vuln_count]).to eq(15)
          expect(result[:medium_vuln_count]).to eq(30)
          expect(result[:low_vuln_count]).to eq(50)
        end
      end
    end

    describe '#serialize_vendor' do
      let!(:vendor) { create(:supply_chain_vendor, account: account) }

      it 'returns serialized vendor data' do
        result = controller_instance.send(:serialize_vendor, vendor)

        expect(result[:id]).to eq(vendor.id)
        expect(result[:name]).to eq(vendor.name)
        expect(result[:vendor_type]).to eq(vendor.vendor_type)
        expect(result[:risk_tier]).to eq(vendor.risk_tier)
        expect(result[:risk_score]).to eq(vendor.risk_score)
        expect(result[:status]).to eq(vendor.status)
        expect(result[:certifications]).to eq(vendor.certifications)
        expect(result[:handles_pii]).to eq(vendor.handles_pii)
        expect(result[:handles_phi]).to eq(vendor.handles_phi)
        expect(result[:handles_pci]).to eq(vendor.handles_pci)
        expect(result[:contract_start_date]).to eq(vendor.contract_start_date)
        expect(result[:contract_end_date]).to eq(vendor.contract_end_date)
        expect(result[:created_at]).to be_present
      end

      context 'with critical risk vendor' do
        let!(:critical_vendor) do
          create(:supply_chain_vendor,
                 :critical_risk,
                 account: account,
                 handles_pii: true,
                 handles_phi: true,
                 handles_pci: true)
        end

        it 'includes sensitive data flags' do
          result = controller_instance.send(:serialize_vendor, critical_vendor)

          expect(result[:risk_tier]).to eq('critical')
          expect(result[:handles_pii]).to be true
          expect(result[:handles_phi]).to be true
          expect(result[:handles_pci]).to be true
        end
      end
    end

    describe '#serialize_report' do
      let(:report_creator) { create(:user, account: account) }
      let!(:report) do
        build(:supply_chain_report, :completed, account: account, created_by: report_creator).tap do |r|
          r.save(validate: false)
        end
      end

      it 'returns serialized report data' do
        result = controller_instance.send(:serialize_report, report)

        expect(result[:id]).to eq(report.id)
        expect(result[:name]).to eq(report.name)
        expect(result[:report_type]).to eq(report.report_type)
        expect(result[:format]).to eq(report.format)
        expect(result[:status]).to eq(report.status)
        expect(result[:generated_at]).to be_present
        expect(result[:file_size]).to eq(report.file_size_bytes)
        expect(result[:created_at]).to be_present
      end

      context 'with different report types' do
        let!(:vulnerability_report) do
          build(:supply_chain_report,
                 :vulnerability_report,
                 :completed,
                 account: account,
                 created_by: report_creator).tap do |r|
            r.save(validate: false)
          end
        end

        it 'serializes vulnerability report correctly' do
          result = controller_instance.send(:serialize_report, vulnerability_report)

          expect(result[:report_type]).to eq('vulnerability_report')
          expect(result[:format]).to eq('pdf')
        end
      end

      context 'with pending report' do
        let!(:pending_report) do
          build(:supply_chain_report, :pending, account: account, created_by: report_creator).tap do |r|
            r.save(validate: false)
          end
        end

        it 'serializes pending report without generated_at' do
          result = controller_instance.send(:serialize_report, pending_report)

          expect(result[:status]).to eq('pending')
          expect(result[:generated_at]).to be_nil
        end
      end
    end
  end
end
