# frozen_string_literal: true

module Api
  module V1
    module Devops
      module Swarm
        class EventsController < ApplicationController
          include AuditLogging

          before_action :set_cluster

          # GET /api/v1/devops/swarm/clusters/:cluster_id/events
          def index
            scope = @cluster.swarm_events

            scope = scope.by_severity(params[:severity]) if params[:severity].present?
            scope = scope.where(event_type: params[:event_type]) if params[:event_type].present?
            scope = scope.where(source_type: params[:source_type]) if params[:source_type].present?
            scope = scope.unacknowledged if params[:unacknowledged] == "true"
            scope = scope.since(Time.zone.parse(params[:since])) if params[:since].present?
            scope = scope.recent

            render_success(items: scope.limit(params[:limit]&.to_i || 100).map(&:event_summary))
          end

          # GET /api/v1/devops/swarm/clusters/:cluster_id/events/:id
          def show
            event = @cluster.swarm_events.find(params[:id])
            render_success(event: event.event_details)
          end

          # POST /api/v1/devops/swarm/clusters/:cluster_id/events/:id/acknowledge
          def acknowledge
            event = @cluster.swarm_events.find(params[:id])
            event.acknowledge!(current_user)

            render_success(event: event.event_details)
            log_audit_event("swarm.events.acknowledge", event)
          end

          private

          def set_cluster
            @cluster = current_user.account.devops_swarm_clusters.find(params[:cluster_id])
          end
        end
      end
    end
  end
end
