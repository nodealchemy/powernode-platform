# frozen_string_literal: true

module Api
  module V1
    module SupplyChain
      class SbomsController < BaseController
        before_action :require_read_permission, only: [ :index, :show, :components, :vulnerabilities, :compliance_status, :statistics ]
        before_action :require_write_permission, only: [ :create, :update, :destroy, :export, :correlate_vulnerabilities, :calculate_risk ]
        before_action :set_sbom, only: [ :show, :update, :destroy, :components, :vulnerabilities, :export, :compliance_status, :correlate_vulnerabilities, :calculate_risk ]

        # GET /api/v1/supply_chain/sboms
        def index
          sboms = current_account.supply_chain_sboms
                                 .includes(:repository)
                                 .order(created_at: :desc)

          sboms = sboms.where(status: params[:status]) if params[:status].present?
          sboms = sboms.where(format: params[:format]) if params[:format].present?
          sboms = sboms.where(repository_id: params[:repository_id]) if params[:repository_id].present?

          sboms = sboms.page(params[:page]).per(params[:per_page] || 20)

          render_success({
            sboms: sboms.map { |s| serialize_sbom(s, include_repository: true) },
            meta: {
              total: sboms.total_count,
              page: sboms.current_page,
              per_page: sboms.limit_value,
              total_pages: sboms.total_pages
            }
          })
        rescue StandardError => e
          Rails.logger.error "[SbomsController] List failed: #{e.message}"
          render_error("Failed to list SBOMs", status: :internal_server_error)
        end

        # GET /api/v1/supply_chain/sboms/:id
        def show
          render_success({
            sbom: serialize_sbom(@sbom, include_repository: true)
          })

          log_audit_event("supply_chain.sboms.read", @sbom)
        end

        # POST /api/v1/supply_chain/sboms
        def create
          repository = params[:repository_id].present? ? current_account.devops_repositories.find(params[:repository_id]) : nil

          sbom = ::SupplyChain::SbomGenerationService.new(
            account: current_account,
            repository: repository,
            options: {
              user: current_user,
              name: params[:name],
              version: params[:version]
            }
          ).generate(
            source_path: params[:source_path],
            ecosystems: params[:ecosystems],
            format: params[:format] || "cyclonedx_1_5"
          )

          render_success({
            sbom: serialize_sbom(sbom),
            message: "SBOM generated successfully"
          }, status: :created)

          log_audit_event("supply_chain.sboms.create", sbom)
        rescue StandardError => e
          Rails.logger.error "[SbomsController] Create failed: #{e.message}"
          render_error("Failed to generate SBOM: #{e.message}", status: :unprocessable_content)
        end

        # PATCH/PUT /api/v1/supply_chain/sboms/:id
        def update
          if @sbom.update(sbom_params)
            render_success({
              sbom: serialize_sbom(@sbom),
              message: "SBOM updated successfully"
            })

            log_audit_event("supply_chain.sboms.update", @sbom)
          else
            render_validation_error(@sbom.errors)
          end
        end

        # DELETE /api/v1/supply_chain/sboms/:id
        def destroy
          @sbom.destroy!

          render_success({ message: "SBOM deleted successfully" })

          log_audit_event("supply_chain.sboms.delete", @sbom)
        rescue StandardError => e
          render_error("Failed to delete SBOM", status: :internal_server_error)
        end

        # GET /api/v1/supply_chain/sboms/:id/components
        def components
          components = @sbom.components.order(depth: :asc, name: :asc)
          components = components.where(dependency_type: params[:type]) if params[:type].present?
          components = components.where(ecosystem: params[:ecosystem]) if params[:ecosystem].present?
          components = components.where(has_known_vulnerabilities: true) if params[:vulnerable] == "true"

          components = components.page(params[:page]).per(params[:per_page] || 50)

          render_success({
            components: components.map { |c| serialize_component(c) },
            meta: {
              total: components.total_count,
              page: components.current_page,
              per_page: components.limit_value
            }
          })
        end

        # GET /api/v1/supply_chain/sboms/:id/vulnerabilities
        def vulnerabilities
          vulns = @sbom.vulnerabilities.includes(:component).order(cvss_score: :desc)
          vulns = vulns.where(severity: params[:severity]) if params[:severity].present?
          vulns = vulns.where(remediation_status: params[:status]) if params[:status].present?

          vulns = vulns.page(params[:page]).per(params[:per_page] || 50)

          render_success({
            vulnerabilities: vulns.map { |v| serialize_vulnerability(v) },
            meta: {
              total: vulns.total_count,
              by_severity: {
                critical: @sbom.vulnerabilities.where(severity: "critical").count,
                high: @sbom.vulnerabilities.where(severity: "high").count,
                medium: @sbom.vulnerabilities.where(severity: "medium").count,
                low: @sbom.vulnerabilities.where(severity: "low").count
              }
            }
          })
        end

        # POST /api/v1/supply_chain/sboms/:id/export
        def export
          format = params[:export_format] || "json"
          document = @sbom.export(format: format.to_sym)

          render_success({
            format: format,
            document: document,
            filename: "#{@sbom.name || @sbom.sbom_id}.#{format}"
          })

          log_audit_event("supply_chain.sboms.export", @sbom)
        end

        # GET /api/v1/supply_chain/sboms/:id/compliance_status
        def compliance_status
          render_success({
            sbom_id: @sbom.id,
            ntia_compliant: @sbom.ntia_minimum_compliant,
            ntia_compliance_details: @sbom.ntia_compliance_details,
            risk_score: @sbom.risk_score,
            vulnerability_summary: {
              total: @sbom.vulnerability_count,
              critical: @sbom.vulnerabilities.where(severity: "critical").count,
              high: @sbom.vulnerabilities.where(severity: "high").count,
              medium: @sbom.vulnerabilities.where(severity: "medium").count,
              low: @sbom.vulnerabilities.where(severity: "low").count
            }
          })
        end

        # POST /api/v1/supply_chain/sboms/:id/correlate_vulnerabilities
        def correlate_vulnerabilities
          count = ::SupplyChain::VulnerabilityCorrelationService.new(sbom: @sbom).correlate!

          render_success({
            sbom_id: @sbom.id,
            vulnerabilities_found: count,
            message: "Vulnerability correlation completed"
          })

          log_audit_event("supply_chain.sboms.correlate_vulnerabilities", @sbom)
        rescue StandardError => e
          render_error("Correlation failed: #{e.message}", status: :unprocessable_content)
        end

        # POST /api/v1/supply_chain/sboms/:id/calculate_risk
        def calculate_risk
          result = ::SupplyChain::RiskCalculationService.new(sbom: @sbom).calculate!

          render_success({
            sbom_id: @sbom.id,
            risk_score: result[:overall_score],
            risk_breakdown: result,
            message: "Risk calculation completed"
          })

          log_audit_event("supply_chain.sboms.calculate_risk", @sbom)
        rescue StandardError => e
          render_error("Risk calculation failed: #{e.message}", status: :unprocessable_content)
        end

        # GET /api/v1/supply_chain/sboms/statistics
        def statistics
          sboms = current_account.supply_chain_sboms

          render_success({
            total_sboms: sboms.count,
            total_components: sboms.sum(:component_count),
            total_vulnerabilities: sboms.sum(:vulnerability_count),
            average_risk_score: sboms.average(:risk_score)&.round(2),
            ntia_compliant_count: sboms.where(ntia_minimum_compliant: true).count,
            by_format: sboms.group(:format).count,
            by_status: sboms.group(:status).count
          })
        end

        private

        def set_sbom
          @sbom = current_account.supply_chain_sboms.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render_error("SBOM not found", status: :not_found)
        end

        def sbom_params
          params.require(:sbom).permit(:name, :version, :status)
        end

        def serialize_component(component)
          {
            id: component.id,
            purl: component.purl,
            name: component.name,
            version: component.version,
            ecosystem: component.ecosystem,
            dependency_type: component.dependency_type,
            depth: component.depth,
            license_spdx_id: component.license_spdx_id,
            license_compliance_status: component.license_compliance_status,
            risk_score: component.risk_score,
            has_known_vulnerabilities: component.has_known_vulnerabilities,
            is_outdated: component.is_outdated
          }
        end

        def serialize_vulnerability(vuln)
          {
            id: vuln.id,
            vulnerability_id: vuln.vulnerability_id,
            severity: vuln.severity,
            cvss_score: vuln.cvss_score,
            cvss_vector: vuln.cvss_vector,
            contextual_score: vuln.contextual_score,
            remediation_status: vuln.remediation_status,
            fixed_version: vuln.fixed_version,
            component: vuln.component.present? ? {
              id: vuln.component.id,
              name: vuln.component.name,
              version: vuln.component.version
            } : nil,
            published_at: vuln.published_at
          }
        end
      end
    end
  end
end
