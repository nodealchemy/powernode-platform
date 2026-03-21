# frozen_string_literal: true

module Api
  module V1
    module System
      class NodeMountPointsController < BaseController
        before_action :set_mount_point, only: [:show, :update, :destroy]

        # GET /api/v1/system/node_mount_points
        def index
          authorize_permission!('system.modules.read')

          mount_points = current_account.system_node_mount_points
          mount_points = apply_filters(mount_points)
          mount_points = paginate(mount_points.by_name)

          render_success(
            mount_points: mount_points.map { |mp| ::System::NodeMountPointSerializer.new(mp).as_json },
            meta: pagination_meta
          )
        end

        # GET /api/v1/system/node_mount_points/:id
        def show
          authorize_permission!('system.modules.read')
          render_success(mount_point: ::System::NodeMountPointSerializer.new(@mount_point).as_json)
        end

        # POST /api/v1/system/node_mount_points
        def create
          authorize_permission!('system.modules.create')

          mount_point = current_account.system_node_mount_points.build(mount_point_params)

          if mount_point.save
            render_success(mount_point: ::System::NodeMountPointSerializer.new(mount_point).as_json, status: :created)
          else
            render_validation_error(mount_point)
          end
        end

        # PATCH/PUT /api/v1/system/node_mount_points/:id
        def update
          authorize_permission!('system.modules.update')

          if @mount_point.update(mount_point_params)
            render_success(mount_point: ::System::NodeMountPointSerializer.new(@mount_point).as_json)
          else
            render_validation_error(@mount_point)
          end
        end

        # DELETE /api/v1/system/node_mount_points/:id
        def destroy
          authorize_permission!('system.modules.delete')

          if @mount_point.instance_mount_points.exists?
            render_error('Cannot delete mount point that is in use', status: :unprocessable_entity)
          else
            @mount_point.destroy
            render_success(message: 'Mount point deleted successfully')
          end
        end

        private

        def set_mount_point
          @mount_point = current_account.system_node_mount_points.find(params[:id])
        end

        def mount_point_params
          params.require(:mount_point).permit(
            :name, :description, :mount_path, :mount_type, :source,
            :enabled, :auto_mount, options: {}
          )
        end

        def apply_filters(mount_points)
          mount_points = mount_points.enabled if params[:enabled] == 'true'
          mount_points = mount_points.disabled if params[:enabled] == 'false'
          mount_points = mount_points.auto_mount if params[:auto_mount] == 'true'
          mount_points = mount_points.by_type(params[:mount_type]) if params[:mount_type].present?
          mount_points = mount_points.where('name ILIKE ?', "%#{params[:search]}%") if params[:search].present?
          mount_points
        end
      end
    end
  end
end
