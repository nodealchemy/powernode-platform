# frozen_string_literal: true

module Api
  module V1
    module Mcp
      class QuotasController < ApplicationController
        include AuditLogging

        # GET /api/v1/mcp/quotas
        def show
          quota = ::Mcp::ResourceQuota.for_account(current_user.account)
          service = ::Mcp::QuotaService.new(current_user.account)

          render_success(
            quota: quota.quota_summary,
            quota_status: service.status,
            resource_limits: service.resource_limits,
            network_allowed: service.network_allowed?,
            overage_cost: service.overage_cost
          )
        end

        # PATCH/PUT /api/v1/mcp/quotas
        def update
          # Only admins can update quotas
          unless current_user.has_permission?("mcp.quotas.manage")
            render_error("You don't have permission to manage quotas", status: :forbidden)
            return
          end

          service = ::Mcp::QuotaService.new(current_user.account)
          service.update_limits!(quota_params)

          render_success(
            quota: service.quota.reload.quota_summary,
            message: "Quota updated successfully"
          )
          log_audit_event("mcp.quotas.update", current_user.account)
        rescue ActiveRecord::RecordInvalid => e
          render_error(e.record.errors.full_messages, status: :unprocessable_entity)
        end

        # POST /api/v1/mcp/quotas/reset_usage
        def reset_usage
          # Only admins can reset usage
          unless current_user.has_permission?("mcp.quotas.manage")
            render_error("You don't have permission to manage quotas", status: :forbidden)
            return
          end

          service = ::Mcp::QuotaService.new(current_user.account)
          service.reset_usage!

          render_success(
            quota: service.quota.reload.quota_summary,
            message: "Usage counters reset successfully"
          )
          log_audit_event("mcp.quotas.reset_usage", current_user.account)
        end

        # GET /api/v1/mcp/quotas/usage_history
        def usage_history
          account = current_user.account

          # Get daily usage for the past 30 days
          daily_usage = account.mcp_container_instances
                               .where("created_at >= ?", 30.days.ago)
                               .group("DATE(created_at)")
                               .count

          # Get hourly usage for the past 24 hours
          hourly_usage = account.mcp_container_instances
                                .where("created_at >= ?", 24.hours.ago)
                                .group("DATE_TRUNC('hour', created_at)")
                                .count

          render_success(
            daily_usage: daily_usage.transform_keys(&:to_s),
            hourly_usage: hourly_usage.transform_keys { |k| k.strftime("%Y-%m-%d %H:00") }
          )
        end

        # GET /api/v1/mcp/quotas/overage
        def overage
          service = ::Mcp::QuotaService.new(current_user.account)
          quota = service.quota

          render_success(
            allow_overage: quota.allow_overage,
            overage_rate: quota.overage_rate_per_container,
            current_overage_cost: service.overage_cost,
            containers_over_limit: [ quota.containers_used_today - quota.max_containers_per_day, 0 ].max
          )
        end

        # PATCH /api/v1/mcp/quotas/overage
        def update_overage
          # Only admins can update overage settings
          unless current_user.has_permission?("mcp.quotas.manage")
            render_error("You don't have permission to manage quotas", status: :forbidden)
            return
          end

          quota = ::Mcp::ResourceQuota.for_account(current_user.account)
          quota.update!(
            allow_overage: params[:allow_overage],
            overage_rate_per_container: params[:overage_rate]
          )

          render_success(
            allow_overage: quota.allow_overage,
            overage_rate: quota.overage_rate_per_container,
            message: "Overage settings updated successfully"
          )
          log_audit_event("mcp.quotas.update_overage", current_user.account)
        end

        private

        def quota_params
          params.require(:quota).permit(
            :max_concurrent_containers,
            :max_containers_per_hour,
            :max_containers_per_day,
            :max_memory_mb,
            :max_cpu_millicores,
            :max_storage_bytes,
            :max_execution_time_seconds,
            :allow_network_access,
            :allow_overage,
            :overage_rate_per_container,
            allowed_egress_domains: []
          )
        end
      end
    end
  end
end
