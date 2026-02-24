# frozen_string_literal: true

module Api
  module V1
    module Ai
      module Security
        class QuarantineController < ApplicationController
          before_action :authenticate_request
          before_action :validate_permissions

          # GET /api/v1/ai/security/quarantine
          def index
            records = ::Ai::QuarantineRecord.where(account: current_account)
            records = records.for_agent(params[:agent_id]) if params[:agent_id].present?
            records = records.where(status: params[:status]) if params[:status].present?
            records = records.by_severity(params[:severity]) if params[:severity].present?
            records = records.order(created_at: :desc)

            page_params = pagination_params
            total = records.count
            items = records.offset((page_params[:page] - 1) * page_params[:per_page])
                           .limit(page_params[:per_page])

            render_success(data: {
              items: items.map { |r| quarantine_json(r) },
              pagination: {
                current_page: page_params[:page],
                per_page: page_params[:per_page],
                total_count: total,
                total_pages: (total.to_f / page_params[:per_page]).ceil
              }
            })
          end

          # GET /api/v1/ai/security/quarantine/:id
          def show
            record = ::Ai::QuarantineRecord.where(account: current_account).find(params[:id])
            render_success(data: quarantine_json(record))
          rescue ActiveRecord::RecordNotFound
            render_not_found("QuarantineRecord")
          end

          # POST /api/v1/ai/security/quarantine
          def quarantine_agent
            agent = current_account.ai_agents.find(params[:agent_id])
            record = quarantine_service.quarantine!(
              agent: agent,
              severity: params[:severity] || "medium",
              reason: params[:reason],
              source: params[:source] || "manual"
            )

            render_success(data: quarantine_json(record), status: :created)
          rescue ActiveRecord::RecordNotFound
            render_not_found("Agent")
          rescue ::Ai::Security::QuarantineService::QuarantineError => e
            render_error(e.message, status: :unprocessable_content)
          end

          # POST /api/v1/ai/security/quarantine/:id/escalate
          def escalate
            record = ::Ai::QuarantineRecord.where(account: current_account).find(params[:id])
            new_record = quarantine_service.escalate!(
              quarantine_record: record,
              new_severity: params[:new_severity]
            )

            render_success(data: quarantine_json(new_record))
          rescue ActiveRecord::RecordNotFound
            render_not_found("QuarantineRecord")
          rescue ::Ai::Security::QuarantineService::QuarantineError => e
            render_error(e.message, status: :unprocessable_content)
          end

          # POST /api/v1/ai/security/quarantine/:id/restore
          def restore
            record = ::Ai::QuarantineRecord.where(account: current_account).find(params[:id])
            restored = quarantine_service.restore!(
              quarantine_record: record,
              approved_by: current_user
            )

            render_success(data: quarantine_json(restored))
          rescue ActiveRecord::RecordNotFound
            render_not_found("QuarantineRecord")
          rescue ::Ai::Security::QuarantineService::QuarantineError => e
            render_error(e.message, status: :unprocessable_content)
          end

          # GET /api/v1/ai/security/quarantine/report
          def security_report
            period = (params[:period_days] || 30).to_i.days
            report = audit_service.security_report(account: current_account, period: period)

            render_success(data: report)
          rescue StandardError => e
            Rails.logger.error("#{self.class.name}##{action_name} failed: #{e.message}")
            render_error(e.message, status: :unprocessable_content)
          end

          # GET /api/v1/ai/security/quarantine/compliance
          def compliance_matrix
            matrix = audit_service.compliance_matrix(account: current_account)

            render_success(data: { matrix: matrix })
          rescue StandardError => e
            Rails.logger.error("#{self.class.name}##{action_name} failed: #{e.message}")
            render_error(e.message, status: :unprocessable_content)
          end

          private

          def validate_permissions
            return if current_worker

            require_permission("ai.security.manage")
          end

          def quarantine_service
            @quarantine_service ||= ::Ai::Security::QuarantineService.new(account: current_account)
          end

          def audit_service
            @audit_service ||= ::Ai::Security::SecurityAuditService.new(account: current_account)
          end

          def quarantine_json(record)
            {
              id: record.id,
              agent_id: record.agent_id,
              severity: record.severity,
              status: record.status,
              trigger_reason: record.trigger_reason,
              trigger_source: record.trigger_source,
              restrictions_applied: record.restrictions_applied,
              forensic_snapshot: record.forensic_snapshot,
              escalated_from_id: record.escalated_from_id,
              approved_by_id: record.approved_by_id,
              restored_at: record.restored_at&.iso8601,
              scheduled_restore_at: record.scheduled_restore_at&.iso8601,
              cooldown_minutes: record.cooldown_minutes,
              restoration_notes: record.restoration_notes,
              created_at: record.created_at.iso8601,
              updated_at: record.updated_at.iso8601
            }
          end
        end
      end
    end
  end
end
