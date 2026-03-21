# frozen_string_literal: true

module Api
  module V1
    module System
      module NodeApi
        # Mount point configuration for node instances
        # Provides mount point data for filesystem mounting
        class MountPointsController < BaseController
          before_action :set_mount_point, only: [:show]

          # GET /api/v1/system/node_api/mount_points
          # List mount points for this instance
          def index
            mount_points = instance_mount_points.includes(:mount_point)
                                                .order("system_node_mount_points.priority")

            render_success(
              mount_points: mount_points.map { |imp| serialize_instance_mount_point(imp) },
              count: mount_points.size
            )
          end

          # GET /api/v1/system/node_api/mount_points/:id
          # Get specific mount point details
          def show
            render_success(mount_point: serialize_mount_point_full(@mount_point))
          end

          private

          def set_mount_point
            @mount_point = instance_mount_points.find_by(mount_point_id: params[:id])&.mount_point

            unless @mount_point
              render_record_not_found("MountPoint")
            end
          end

          def instance_mount_points
            current_instance.instance_mount_points
          end

          def serialize_instance_mount_point(instance_mount_point)
            mp = instance_mount_point.mount_point
            {
              id: mp.id,
              name: mp.name,
              mount_path: mp.mount_path,
              mount_type: mp.mount_type,
              mount_options: mp.mount_options,
              priority: mp.priority,
              enabled: instance_mount_point.enabled,
              config: instance_mount_point.config
            }
          end

          def serialize_mount_point_full(mount_point)
            {
              id: mount_point.id,
              name: mount_point.name,
              mount_path: mount_point.mount_path,
              mount_type: mount_point.mount_type,
              mount_options: mount_point.mount_options,
              device_key: mount_point.device_key,
              priority: mount_point.priority,
              config: mount_point.config,
              fsck_order: mount_point.respond_to?(:fsck_order) ? mount_point.fsck_order : nil
            }
          end
        end
      end
    end
  end
end
