# frozen_string_literal: true

module Api
  module V1
    module System
      module WorkerApi
        # Volume operations for infrastructure workers
        # Handles volume CRUD, attach/detach, and status management
        class VolumesController < BaseController
          before_action :set_volume, only: [:show, :update, :destroy, :attach, :detach, :check]

          # GET /api/v1/system/worker_api/volumes
          # List volumes for account(s) managed by this worker
          def index
            authorize_worker_permission!("system.volumes.read")

            volumes = accessible_volumes
            volumes = apply_filters(volumes)
            volumes = paginate(volumes.includes(:provider_region, :volume_type))

            render_success(
              volumes: volumes.map { |v| serialize_volume(v) },
              meta: pagination_meta
            )
          end

          # GET /api/v1/system/worker_api/volumes/:id
          def show
            authorize_worker_permission!("system.volumes.read")
            render_success(volume: serialize_volume_full(@volume))
          end

          # POST /api/v1/system/worker_api/volumes
          # Create new volume (typically from provisioning)
          def create
            authorize_worker_permission!("system.volumes.create")

            volume = accessible_volumes.new(volume_params)

            if volume.save
              render_success(volume: serialize_volume(volume), status: :created)
            else
              render_validation_error(volume)
            end
          end

          # PUT /api/v1/system/worker_api/volumes/:id
          # Update volume attributes (status, cloud IDs)
          def update
            authorize_worker_permission!("system.volumes.update")

            if @volume.update(volume_update_params)
              render_success(volume: serialize_volume(@volume))
            else
              render_validation_error(@volume)
            end
          end

          # DELETE /api/v1/system/worker_api/volumes/:id
          def destroy
            authorize_worker_permission!("system.volumes.delete")

            if @volume.status == "attached"
              return render_error("Cannot delete attached volume. Detach first.")
            end

            if @volume.destroy
              render_success(message: "Volume deleted successfully")
            else
              render_error("Failed to delete volume: #{@volume.errors.full_messages.join(', ')}")
            end
          end

          # POST /api/v1/system/worker_api/volumes/:id/attach
          # Attach volume to instance
          def attach
            authorize_worker_permission!("system.volumes.manage")

            instance_id = params[:instance_id]
            device_name = params[:device_name]

            unless instance_id.present?
              return render_error("instance_id is required")
            end

            instance = find_accessible_instance(instance_id)
            return unless instance

            service = ::System::VolumeManagementService.new(@volume)
            result = service.attach(instance, device_name: device_name)

            if result[:success]
              render_success(
                volume: serialize_volume(@volume.reload),
                attached_to: instance_id,
                device_name: result[:device_name]
              )
            else
              render_error(result[:error] || "Failed to attach volume")
            end
          end

          # POST /api/v1/system/worker_api/volumes/:id/detach
          # Detach volume from instance
          def detach
            authorize_worker_permission!("system.volumes.manage")

            service = ::System::VolumeManagementService.new(@volume)
            result = service.detach

            if result[:success]
              render_success(
                volume: serialize_volume(@volume.reload),
                detached: true
              )
            else
              render_error(result[:error] || "Failed to detach volume")
            end
          end

          # POST /api/v1/system/worker_api/volumes/:id/check
          # Check volume status and sync with cloud provider
          def check
            authorize_worker_permission!("system.volumes.manage")

            service = ::System::VolumeManagementService.new(@volume)
            result = service.check_status

            if result[:success]
              render_success(
                volume: serialize_volume(@volume.reload),
                cloud_status: result[:cloud_status],
                synced: result[:synced]
              )
            else
              render_error(result[:error] || "Failed to check volume status")
            end
          end

          # GET /api/v1/system/worker_api/volumes/for_instance/:instance_id
          # Get all volumes attached to an instance
          def for_instance
            authorize_worker_permission!("system.volumes.read")

            instance = find_accessible_instance(params[:instance_id])
            return unless instance

            volumes = accessible_volumes.where(
              "attached_instance_id = ? OR config->>'attached_to' = ?",
              instance.id,
              instance.id
            )

            render_success(
              instance_id: instance.id,
              volumes: volumes.map { |v| serialize_volume(v) }
            )
          end

          private

          def set_volume
            @volume = accessible_volumes.find(params[:id])
          rescue ActiveRecord::RecordNotFound
            render_record_not_found("ProviderVolume")
          end

          def accessible_volumes
            # Get volumes for accounts that have nodes managed by this worker
            account_ids = ::System::Node.where(worker: current_worker)
                                        .joins(:account)
                                        .pluck(:account_id)
                                        .uniq

            ::System::ProviderVolume.where(account_id: account_ids)
          end

          def find_accessible_instance(instance_id)
            ::System::NodeInstance
              .joins(:node)
              .where(system_nodes: { worker_id: current_worker.id })
              .find(instance_id)
          rescue ActiveRecord::RecordNotFound
            render_record_not_found("NodeInstance")
            nil
          end

          def volume_params
            params.require(:volume).permit(
              :name, :size_gb, :status,
              :provider_region_id, :volume_type_id, :account_id,
              :cloud_volume_id, :availability_zone_id,
              config: {}
            )
          end

          def volume_update_params
            params.require(:volume).permit(
              :status, :cloud_volume_id,
              config: {}
            )
          end

          def apply_filters(scope)
            scope = scope.where(status: params[:status]) if params[:status].present?
            scope = scope.where(provider_region_id: params[:region_id]) if params[:region_id].present?
            scope = scope.where(volume_type_id: params[:type_id]) if params[:type_id].present?
            scope.order(created_at: :desc)
          end

          def serialize_volume(volume)
            {
              id: volume.id,
              name: volume.name,
              size_gb: volume.size_gb,
              status: volume.status,
              cloud_volume_id: volume.cloud_volume_id,
              provider_region_id: volume.provider_region_id,
              volume_type_id: volume.volume_type_id,
              account_id: volume.account_id,
              created_at: volume.created_at,
              updated_at: volume.updated_at
            }
          end

          def serialize_volume_full(volume)
            serialize_volume(volume).merge(
              config: volume.config,
              provider_region: volume.provider_region ? {
                id: volume.provider_region.id,
                name: volume.provider_region.name,
                region_code: volume.provider_region.region_code
              } : nil,
              volume_type: volume.volume_type ? {
                id: volume.volume_type.id,
                name: volume.volume_type.name,
                volume_type: volume.volume_type.volume_type
              } : nil,
              snapshots: volume.snapshots.map { |s| serialize_snapshot(s) }
            )
          end

          def serialize_snapshot(snapshot)
            {
              id: snapshot.id,
              name: snapshot.name,
              status: snapshot.status,
              size_gb: snapshot.size_gb,
              created_at: snapshot.created_at
            }
          end
        end
      end
    end
  end
end
