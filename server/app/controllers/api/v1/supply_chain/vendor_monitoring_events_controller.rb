# frozen_string_literal: true

module Api
  module V1
    module SupplyChain
      class VendorMonitoringEventsController < BaseController
        before_action :require_read_permission, only: [:index, :show]
        before_action :require_write_permission, only: [:acknowledge, :dismiss]
        before_action :set_event, only: [:show, :acknowledge, :dismiss]

        # GET /api/v1/supply_chain/vendor_monitoring_events
        def index
          @events = current_account.supply_chain_vendor_monitoring_events
                                   .includes(:vendor, :acknowledged_by)
                                   .order(created_at: :desc)

          @events = @events.where(event_type: params[:event_type]) if params[:event_type].present?
          @events = @events.where(severity: params[:severity]) if params[:severity].present?
          @events = @events.where(vendor_id: params[:vendor_id]) if params[:vendor_id].present?
          @events = @events.where(acknowledged: false) if params[:unacknowledged] == "true"
          @events = @events.where(dismissed: false) if params[:active] == "true"

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
            return render_error("Event already acknowledged", status: :unprocessable_entity)
          end

          @event.acknowledge!(current_user, params[:notes])

          render_success(
            { vendor_monitoring_event: serialize_event(@event) },
            message: "Event acknowledged"
          )
        end

        # POST /api/v1/supply_chain/vendor_monitoring_events/:id/dismiss
        def dismiss
          if @event.dismissed?
            return render_error("Event already dismissed", status: :unprocessable_entity)
          end

          if params[:reason].blank?
            return render_error("Dismissal reason is required", status: :unprocessable_entity)
          end

          @event.dismiss!(current_user, params[:reason])

          render_success(
            { vendor_monitoring_event: serialize_event(@event) },
            message: "Event dismissed"
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
            event_id: event.event_id,
            event_type: event.event_type,
            severity: event.severity,
            title: event.title,
            summary: event.summary,
            vendor: event.vendor ? {
              id: event.vendor.id,
              name: event.vendor.name,
              risk_tier: event.vendor.risk_tier
            } : nil,
            source: event.source,
            detected_at: event.detected_at,
            acknowledged: event.acknowledged,
            dismissed: event.dismissed,
            created_at: event.created_at
          }

          if include_details
            data[:description] = event.description
            data[:impact_analysis] = event.impact_analysis
            data[:recommended_actions] = event.recommended_actions
            data[:source_url] = event.source_url
            data[:acknowledged_by] = event.acknowledged_by ? {
              id: event.acknowledged_by.id,
              name: event.acknowledged_by.name
            } : nil
            data[:acknowledged_at] = event.acknowledged_at
            data[:acknowledgment_notes] = event.acknowledgment_notes
            data[:dismissed_by] = event.dismissed_by ? {
              id: event.dismissed_by.id,
              name: event.dismissed_by.name
            } : nil
            data[:dismissed_at] = event.dismissed_at
            data[:dismissal_reason] = event.dismissal_reason
            data[:related_events] = event.related_event_ids
            data[:metadata] = event.metadata
          end

          data
        end
      end
    end
  end
end
