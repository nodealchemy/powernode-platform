# frozen_string_literal: true

module Api
  module V1
    module SupplyChain
      class CveMonitorsController < BaseController
        before_action :set_cve_monitor, only: [:show, :update, :destroy, :run, :alerts]

        # GET /api/v1/supply_chain/cve_monitors
        def index
          @monitors = current_account.supply_chain_cve_monitors
                                     .includes(:created_by)
                                     .order(created_at: :desc)

          @monitors = @monitors.where(is_active: true) if params[:active_only] == "true"
          @monitors = @monitors.where(scope_type: params[:scope_type]) if params[:scope_type].present?

          @monitors = paginate(@monitors)

          render_success(
            cve_monitors: @monitors.map { |m| serialize_monitor(m) },
            meta: pagination_meta(@monitors)
          )
        end

        # GET /api/v1/supply_chain/cve_monitors/:id
        def show
          render_success(cve_monitor: serialize_monitor(@monitor, include_details: true))
        end

        # POST /api/v1/supply_chain/cve_monitors
        def create
          @monitor = current_account.supply_chain_cve_monitors.build(monitor_params)
          @monitor.created_by = current_user

          if @monitor.save
            render_success(cve_monitor: serialize_monitor(@monitor), status: :created)
          else
            render_error(@monitor.errors.full_messages.join(", "), status: :unprocessable_entity)
          end
        end

        # PATCH/PUT /api/v1/supply_chain/cve_monitors/:id
        def update
          if @monitor.update(monitor_params)
            render_success(cve_monitor: serialize_monitor(@monitor))
          else
            render_error(@monitor.errors.full_messages.join(", "), status: :unprocessable_entity)
          end
        end

        # DELETE /api/v1/supply_chain/cve_monitors/:id
        def destroy
          @monitor.destroy
          render_success(message: "CVE monitor deleted")
        end

        # POST /api/v1/supply_chain/cve_monitors/:id/run
        def run
          ::SupplyChain::CveMonitoringJob.perform_later(@monitor.id)

          render_success(
            cve_monitor: serialize_monitor(@monitor),
            message: "CVE monitoring job queued"
          )
        end

        # GET /api/v1/supply_chain/cve_monitors/:id/alerts
        def alerts
          # This would return recent CVE alerts from the monitor
          alerts = @monitor.recent_alerts(limit: params[:limit] || 50)

          render_success(
            cve_monitor_id: @monitor.id,
            alerts: alerts.map { |a| serialize_alert(a) }
          )
        end

        # POST /api/v1/supply_chain/cve_monitors/run_all
        def run_all
          monitors = current_account.supply_chain_cve_monitors.where(is_active: true)
          monitors.each do |monitor|
            ::SupplyChain::CveMonitoringJob.perform_later(monitor.id)
          end

          render_success(
            message: "CVE monitoring jobs queued",
            monitors_queued: monitors.count
          )
        end

        private

        def set_cve_monitor
          @monitor = current_account.supply_chain_cve_monitors.find(params[:id])
        end

        def monitor_params
          params.require(:cve_monitor).permit(
            :name, :description, :scope_type, :scope_id,
            :min_severity, :is_active, :schedule_cron,
            :notify_on_new, :notify_on_upgrade, :notify_on_fix,
            notification_channels: {}, filters: {}, metadata: {}
          )
        end

        def serialize_monitor(monitor, include_details: false)
          data = {
            id: monitor.id,
            name: monitor.name,
            description: monitor.description,
            scope_type: monitor.scope_type,
            scope_id: monitor.scope_id,
            min_severity: monitor.min_severity,
            is_active: monitor.is_active,
            schedule_cron: monitor.schedule_cron,
            last_run_at: monitor.last_run_at,
            next_run_at: monitor.next_run_at,
            created_at: monitor.created_at
          }

          if include_details
            data[:notify_on_new] = monitor.notify_on_new
            data[:notify_on_upgrade] = monitor.notify_on_upgrade
            data[:notify_on_fix] = monitor.notify_on_fix
            data[:notification_channels] = monitor.notification_channels
            data[:filters] = monitor.filters
            data[:alert_count] = monitor.alert_count
            data[:metadata] = monitor.metadata
          end

          data
        end

        def serialize_alert(alert)
          {
            id: alert[:id],
            cve_id: alert[:cve_id],
            severity: alert[:severity],
            alert_type: alert[:alert_type],
            component_name: alert[:component_name],
            component_version: alert[:component_version],
            created_at: alert[:created_at]
          }
        end
      end
    end
  end
end
