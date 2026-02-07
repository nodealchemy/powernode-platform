# frozen_string_literal: true

module Api
  module V1
    module Devops
      module Docker
        class ActivitiesController < ApplicationController
          before_action :set_host

          # GET /api/v1/devops/docker/hosts/:host_id/activities
          def index
            scope = @host.docker_activities

            scope = scope.by_type(params[:activity_type]) if params[:activity_type].present?
            scope = scope.where(status: params[:status]) if params[:status].present?
            scope = scope.for_container(params[:container_id]) if params[:container_id].present?
            scope = scope.for_image(params[:image_id]) if params[:image_id].present?
            scope = scope.order(created_at: :desc)

            page = (params[:page] || 1).to_i
            per_page = (params[:per_page] || 50).to_i
            total = scope.count
            activities = scope.offset((page - 1) * per_page).limit(per_page)

            render_success(
              items: activities.map(&:activity_summary),
              pagination: {
                current_page: page,
                per_page: per_page,
                total_pages: (total.to_f / per_page).ceil,
                total_count: total
              }
            )
          end

          # GET /api/v1/devops/docker/hosts/:host_id/activities/:id
          def show
            activity = @host.docker_activities.find(params[:id])
            render_success(activity: activity.activity_details)
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
