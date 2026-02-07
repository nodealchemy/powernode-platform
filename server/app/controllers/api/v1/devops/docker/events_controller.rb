# frozen_string_literal: true

module Api
  module V1
    module Devops
      module Docker
        class EventsController < ApplicationController
          include AuditLogging

          before_action :set_host

          # GET /api/v1/devops/docker/hosts/:host_id/events
          def index
            scope = @host.docker_events

            scope = scope.by_severity(params[:severity]) if params[:severity].present?
            scope = scope.where(source_type: params[:source_type]) if params[:source_type].present?
            scope = scope.unacknowledged if params[:acknowledged] == "false"
            scope = scope.where(acknowledged: true) if params[:acknowledged] == "true"
            scope = scope.since(Time.parse(params[:since])) if params[:since].present?
            scope = scope.recent

            page = (params[:page] || 1).to_i
            per_page = (params[:per_page] || 50).to_i
            total = scope.count
            events = scope.offset((page - 1) * per_page).limit(per_page)

            render_success(
              items: events.map(&:event_summary),
              pagination: {
                current_page: page,
                per_page: per_page,
                total_pages: (total.to_f / per_page).ceil,
                total_count: total
              }
            )
          end

          # GET /api/v1/devops/docker/hosts/:host_id/events/:id
          def show
            event = @host.docker_events.find(params[:id])
            render_success(event: event.event_details)
          end

          # POST /api/v1/devops/docker/hosts/:host_id/events/:id/acknowledge
          def acknowledge
            event = @host.docker_events.find(params[:id])
            event.acknowledge!(current_user)

            render_success(event: event.event_details)
            log_audit_event("docker.events.acknowledge", @host)
          end

          private

          def set_host
            @host = current_user.account.devops_docker_hosts.find(params[:host_id])
          end
        end
      end
    end
  end
end
