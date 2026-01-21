# frozen_string_literal: true

module Api
  module V1
    module SupplyChain
      class BaseController < ApplicationController
        include AuditLogging

        before_action :authenticate_request

        private

        def require_read_permission
          return if current_user.has_permission?("supply_chain.read")

          render_error("Insufficient permissions to view supply chain data", status: :forbidden)
        end

        def require_write_permission
          return if current_user.has_permission?("supply_chain.write")

          render_error("Insufficient permissions to manage supply chain data", status: :forbidden)
        end

        def require_admin_permission
          return if current_user.has_permission?("supply_chain.admin")

          render_error("Insufficient permissions for supply chain administration", status: :forbidden)
        end

        def current_account
          @current_account ||= current_user.account
        end

        def serialize_sbom(sbom, options = {})
          result = {
            id: sbom.id,
            sbom_id: sbom.sbom_id,
            name: sbom.name,
            version: sbom.version,
            format: sbom.format,
            component_count: sbom.component_count,
            vulnerability_count: sbom.vulnerability_count,
            risk_score: sbom.risk_score,
            ntia_minimum_compliant: sbom.ntia_minimum_compliant,
            status: sbom.status,
            created_at: sbom.created_at,
            updated_at: sbom.updated_at
          }

          if options[:include_repository] && sbom.repository.present?
            result[:repository] = {
              id: sbom.repository.id,
              name: sbom.repository.name,
              full_name: sbom.repository.full_name
            }
          end

          result
        end

        def serialize_attestation(attestation, options = {})
          {
            id: attestation.id,
            attestation_id: attestation.attestation_id,
            attestation_type: attestation.attestation_type,
            slsa_level: attestation.slsa_level,
            subject_name: attestation.subject_name,
            subject_digest: attestation.subject_digest,
            signed: attestation.signed?,
            verified: attestation.verified?,
            rekor_logged: attestation.logged_to_rekor?,
            created_at: attestation.created_at
          }
        end

        def serialize_container_image(image, options = {})
          {
            id: image.id,
            registry: image.registry,
            repository: image.repository,
            tag: image.tag,
            digest: image.digest,
            status: image.status,
            critical_vuln_count: image.critical_vuln_count,
            high_vuln_count: image.high_vuln_count,
            medium_vuln_count: image.medium_vuln_count,
            low_vuln_count: image.low_vuln_count,
            is_deployed: image.is_deployed,
            created_at: image.created_at
          }
        end

        def serialize_vendor(vendor, options = {})
          {
            id: vendor.id,
            name: vendor.name,
            vendor_type: vendor.vendor_type,
            risk_tier: vendor.risk_tier,
            risk_score: vendor.risk_score,
            status: vendor.status,
            certifications: vendor.certifications,
            handles_pii: vendor.handles_pii,
            handles_phi: vendor.handles_phi,
            handles_pci: vendor.handles_pci,
            contract_start_date: vendor.contract_start_date,
            contract_end_date: vendor.contract_end_date,
            created_at: vendor.created_at
          }
        end

        def serialize_report(report, options = {})
          {
            id: report.id,
            name: report.name,
            report_type: report.report_type,
            format: report.format,
            status: report.status,
            generated_at: report.generated_at,
            file_size: report.file_size,
            created_at: report.created_at
          }
        end
      end
    end
  end
end
