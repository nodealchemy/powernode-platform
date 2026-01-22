# frozen_string_literal: true

module Api
  module V1
    module SupplyChain
      class VendorsController < BaseController
        before_action :require_read_permission, only: [:index, :show, :risk_profile, :monitoring_events, :statistics, :risk_dashboard]
        before_action :require_write_permission, only: [:create, :update, :destroy, :assess, :reassess]
        before_action :set_vendor, only: [:show, :update, :destroy, :assess, :reassess, :risk_profile, :monitoring_events]

        # GET /api/v1/supply_chain/vendors
        def index
          vendors = current_account.supply_chain_vendors
                                   .order(created_at: :desc)

          vendors = vendors.where(status: params[:status]) if params[:status].present?
          vendors = vendors.where(vendor_type: params[:type]) if params[:type].present?
          vendors = vendors.where(risk_tier: params[:risk_tier]) if params[:risk_tier].present?

          vendors = vendors.page(params[:page]).per(params[:per_page] || 20)

          render_success({
            vendors: vendors.map { |v| serialize_vendor(v) },
            meta: {
              total: vendors.total_count,
              page: vendors.current_page,
              per_page: vendors.limit_value
            }
          })
        rescue StandardError => e
          Rails.logger.error "[VendorsController] List failed: #{e.message}"
          render_error("Failed to list vendors", status: :internal_server_error)
        end

        # GET /api/v1/supply_chain/vendors/:id
        def show
          render_success({
            vendor: serialize_vendor_detail(@vendor)
          })

          log_audit_event("supply_chain.vendors.read", @vendor)
        end

        # POST /api/v1/supply_chain/vendors
        def create
          vendor = current_account.supply_chain_vendors.new(vendor_params)

          if vendor.save
            render_success({
              vendor: serialize_vendor(vendor),
              message: "Vendor created successfully"
            }, status: :created)

            log_audit_event("supply_chain.vendors.create", vendor)
          else
            render_validation_error(vendor.errors)
          end
        end

        # PATCH/PUT /api/v1/supply_chain/vendors/:id
        def update
          if @vendor.update(vendor_params)
            render_success({
              vendor: serialize_vendor(@vendor),
              message: "Vendor updated successfully"
            })

            log_audit_event("supply_chain.vendors.update", @vendor)
          else
            render_validation_error(@vendor.errors)
          end
        end

        # DELETE /api/v1/supply_chain/vendors/:id
        def destroy
          @vendor.destroy!

          render_success({ message: "Vendor deleted successfully" })

          log_audit_event("supply_chain.vendors.delete", @vendor)
        rescue StandardError => e
          render_error("Failed to delete vendor", status: :internal_server_error)
        end

        # POST /api/v1/supply_chain/vendors/:id/assess
        def assess
          assessment = ::SupplyChain::VendorRiskService.new(
            account: current_account,
            vendor: @vendor,
            options: { user: current_user }
          ).assess!

          render_success({
            vendor_id: @vendor.id,
            assessment: serialize_assessment(assessment),
            message: "Risk assessment completed"
          })

          log_audit_event("supply_chain.vendors.assess", @vendor)
        rescue StandardError => e
          Rails.logger.error "[VendorsController] Assessment failed: #{e.message}"
          render_error("Assessment failed: #{e.message}", status: :unprocessable_content)
        end

        # POST /api/v1/supply_chain/vendors/:id/reassess
        def reassess
          assessment = ::SupplyChain::VendorRiskService.new(
            account: current_account,
            vendor: @vendor,
            options: { user: current_user }
          ).reassess!

          render_success({
            vendor_id: @vendor.id,
            assessment: serialize_assessment(assessment),
            message: "Periodic reassessment completed"
          })

          log_audit_event("supply_chain.vendors.reassess", @vendor)
        rescue StandardError => e
          render_error("Reassessment failed: #{e.message}", status: :unprocessable_content)
        end

        # GET /api/v1/supply_chain/vendors/:id/risk_profile
        def risk_profile
          inherent_risk = ::SupplyChain::VendorRiskService.new(
            account: current_account,
            vendor: @vendor
          ).calculate_inherent_risk

          latest_assessment = @vendor.risk_assessments.completed.order(completed_at: :desc).first

          render_success({
            vendor_id: @vendor.id,
            risk_tier: @vendor.risk_tier,
            risk_score: @vendor.risk_score,
            inherent_risk: inherent_risk,
            latest_assessment: latest_assessment.present? ? serialize_assessment(latest_assessment) : nil,
            next_assessment_due: @vendor.next_assessment_due,
            certifications: @vendor.certifications,
            data_handling: {
              handles_pii: @vendor.handles_pii,
              handles_phi: @vendor.handles_phi,
              handles_pci: @vendor.handles_pci
            }
          })
        end

        # GET /api/v1/supply_chain/vendors/:id/monitoring_events
        def monitoring_events
          events = @vendor.monitoring_events.order(created_at: :desc)
          events = events.where(event_type: params[:type]) if params[:type].present?
          events = events.where(severity: params[:severity]) if params[:severity].present?
          events = events.where(is_acknowledged: false) if params[:unacknowledged] == "true"

          events = events.page(params[:page]).per(params[:per_page] || 20)

          render_success({
            events: events.map { |e| serialize_monitoring_event(e) },
            meta: {
              total: events.total_count,
              page: events.current_page,
              unacknowledged_count: @vendor.monitoring_events.where(is_acknowledged: false).count
            }
          })
        end

        # GET /api/v1/supply_chain/vendors/statistics
        def statistics
          vendors = current_account.supply_chain_vendors

          render_success({
            total: vendors.count,
            by_status: vendors.group(:status).count,
            by_type: vendors.group(:vendor_type).count,
            by_risk_tier: vendors.group(:risk_tier).count,
            requiring_assessment: vendors.where(status: "active").select(&:needs_assessment?).count,
            with_expiring_contracts: vendors.where("contract_end_date < ?", 60.days.from_now).count,
            average_risk_score: vendors.where.not(risk_score: nil).average(:risk_score)&.round(2)
          })
        end

        # GET /api/v1/supply_chain/vendors/risk_dashboard
        def risk_dashboard
          vendors = current_account.supply_chain_vendors.where(status: "active")

          critical_vendors = vendors.where(risk_tier: "critical")
          high_risk_vendors = vendors.where(risk_tier: "high")

          render_success({
            summary: {
              total_active: vendors.count,
              critical_count: critical_vendors.count,
              high_risk_count: high_risk_vendors.count,
              assessments_overdue: vendors.select(&:needs_assessment?).count
            },
            critical_vendors: critical_vendors.limit(10).map { |v| serialize_vendor(v) },
            recent_events: current_account.supply_chain_vendor_monitoring_events
                                          .order(created_at: :desc)
                                          .limit(10)
                                          .map { |e| serialize_monitoring_event(e) },
            expiring_contracts: vendors.where("contract_end_date < ?", 60.days.from_now)
                                       .order(contract_end_date: :asc)
                                       .limit(10)
                                       .map { |v| serialize_vendor(v) }
          })
        end

        private

        def set_vendor
          @vendor = current_account.supply_chain_vendors.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render_error("Vendor not found", status: :not_found)
        end

        def vendor_params
          params.require(:vendor).permit(
            :name,
            :vendor_type,
            :status,
            :description,
            :website,
            :contact_email,
            :handles_pii,
            :handles_phi,
            :handles_pci,
            :has_dpa,
            :has_baa,
            :contract_start_date,
            :contract_end_date,
            certifications: [:name, :issuer, :issued_at, :expires_at, :certificate_url],
            security_contacts: [:name, :email, :phone, :role],
            metadata: {}
          )
        end

        def serialize_vendor_detail(vendor)
          serialize_vendor(vendor).merge({
            slug: vendor.slug,
            description: vendor.description,
            website: vendor.website,
            primary_contact: {
              email: vendor.contact_email
            },
            has_dpa: vendor.has_dpa,
            has_baa: vendor.has_baa,
            next_assessment_due: vendor.next_assessment_due,
            last_assessment_date: vendor.last_assessment_at,
            assessment_count: vendor.risk_assessments.count,
            active_questionnaires: vendor.questionnaire_responses.where(status: ["sent", "in_progress"]).count,
            metadata: vendor.metadata
          })
        end

        def serialize_assessment(assessment)
          {
            id: assessment.id,
            assessment_type: assessment.assessment_type,
            status: assessment.status,
            security_score: assessment.security_score,
            compliance_score: assessment.compliance_score,
            operational_score: assessment.operational_score,
            summary: assessment.summary,
            findings_count: assessment.findings&.length || 0,
            recommendations_count: assessment.recommendations&.length || 0,
            assessment_date: assessment.assessment_date,
            completed_at: assessment.completed_at
          }
        end

        def serialize_monitoring_event(event)
          {
            id: event.id,
            event_type: event.event_type,
            severity: event.severity,
            title: event.title,
            description: event.description,
            source: event.source,
            acknowledged: event.is_acknowledged,
            acknowledged_at: event.acknowledged_at,
            created_at: event.created_at
          }
        end
      end
    end
  end
end
