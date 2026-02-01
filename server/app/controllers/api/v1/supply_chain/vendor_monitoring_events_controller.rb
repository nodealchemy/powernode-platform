# frozen_string_literal: true

module Api
  module V1
    module SupplyChain
      class VendorMonitoringEventsController < BaseController
        before_action :require_read_permission, only: [:index, :show]
        before_action :require_write_permission, only: [:acknowledge, :resolve]
        before_action :set_event, only: [:show, :acknowledge, :resolve]

        # GET /api/v1/supply_chain/vendor_monitoring_events
        def index
          @events = current_account.supply_chain_vendor_monitoring_events
                                   .includes(:vendor, :acknowledged_by)
                                   .order(created_at: :desc)

          @events = @events.where(event_type: params[:event_type]) if params[:event_type].present?
          @events = @events.where(severity: params[:severity]) if params[:severity].present?
          @events = @events.where(vendor_id: params[:vendor_id]) if params[:vendor_id].present?
          @events = @events.where(is_acknowledged: false) if params[:unacknowledged] == "true"
          @events = @events.where(resolved_at: nil) if params[:active] == "true"

          @events = paginate(@events)

          render_success(
            { vendor_monitoring_events: @events.map { |e| serialize_event(e) } },
            meta: pagination_meta
          )
        end

        # GET /api/v1/supply_chain/vendor_monitoring_events/:id
        def show
          render_success({ vendor_monitoring_event: serialize_event(@event, include_details: true) })
        end

        # POST /api/v1/supply_chain/vendor_monitoring_events/:id/acknowledge
        def acknowledge
          if @event.acknowledged?
            return render_error("Event already acknowledged", status: :unprocessable_content)
          end

          @event.acknowledge!(current_user)

          render_success(
            { vendor_monitoring_event: serialize_event(@event) },
            message: "Event acknowledged"
          )
        end

        # POST /api/v1/supply_chain/vendor_monitoring_events/:id/resolve
        def resolve
          if @event.resolved?
            return render_error("Event already resolved", status: :unprocessable_content)
          end

          @event.resolve!

          render_success(
            { vendor_monitoring_event: serialize_event(@event) },
            message: "Event resolved"
          )
        end

        private

        def set_event
          @event = current_account.supply_chain_vendor_monitoring_events.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render_error("Vendor monitoring event not found", status: :not_found)
        end

        def serialize_event(event, include_details: false)
          data = {
            id: event.id,
            event_type: event.event_type,
            severity: event.severity,
            title: event.title,
            vendor: event.vendor ? {
              id: event.vendor.id,
              name: event.vendor.name,
              risk_tier: event.vendor.respond_to?(:risk_tier) ? event.vendor.risk_tier : nil
            } : nil,
            source: event.source,
            detected_at: event.detected_at,
            is_acknowledged: event.is_acknowledged,
            resolved_at: event.resolved_at,
            created_at: event.created_at
          }

          if include_details
            data[:description] = event.description
            data[:external_url] = event.external_url
            data[:recommended_actions] = event.recommended_actions
            data[:affected_services] = event.affected_services
            data[:acknowledged_by] = event.acknowledged_by ? {
              id: event.acknowledged_by.id,
              name: event.acknowledged_by.name
            } : nil
            data[:acknowledged_at] = event.acknowledged_at
            data[:metadata] = event.metadata
          end

          data
        end
      end
    end
  end
end
