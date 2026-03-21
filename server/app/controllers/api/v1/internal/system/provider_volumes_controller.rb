# frozen_string_literal: true

module Api
  module V1
    module Internal
      module System
        # Internal API controller for system provider volume operations
        class ProviderVolumesController < BaseController
          before_action :set_volume, except: %i[index]

          # GET /api/v1/internal/system/provider_volumes
          def index
            volumes = ::System::ProviderVolume.all

            volumes = volumes.where(status: params[:status]) if params[:status].present?
            volumes = volumes.where(node_instance_id: params[:node_instance_id]) if params[:node_instance_id].present?

            if params[:for_health_check].present?
              # Include volumes that might need attention
              volumes = volumes.where(status: %w[pending provisioning available attached])
            end

            volumes = volumes.includes(:provider_region, :node_instance)
                             .limit(params[:limit] || 100)

            render_success(
              data: {
                provider_volumes: volumes.map { |v| volume_data(v) }
              }
            )
          end

          # GET /api/v1/internal/system/provider_volumes/:id
          def show
            render_success(data: volume_data(@volume))
          end

          # POST /api/v1/internal/system/provider_volumes/:id/attach
          def attach
            unless @volume.available?
              return render_error("Volume must be in available status to attach", status: :unprocessable_entity)
            end

            unless @volume.node_instance_id.present?
              return render_error("No node instance assigned to volume", status: :unprocessable_entity)
            end

            result = ::System::VolumeManagementService.attach(volume: @volume)

            if result[:success]
              render_success(
                data: {
                  success: true,
                  volume_id: @volume.id,
                  status: @volume.reload.status
                }
              )
            else
              render_error(result[:error], status: :unprocessable_entity)
            end
          rescue StandardError => e
            Rails.logger.error("[System::ProviderVolumes] Attach failed: #{e.message}")
            render_error(e.message, status: :internal_server_error)
          end

          # POST /api/v1/internal/system/provider_volumes/:id/detach
          def detach
            unless @volume.attached?
              return render_error("Volume must be in attached status to detach", status: :unprocessable_entity)
            end

            result = ::System::VolumeManagementService.detach(volume: @volume)

            if result[:success]
              render_success(
                data: {
                  success: true,
                  volume_id: @volume.id,
                  status: @volume.reload.status
                }
              )
            else
              render_error(result[:error], status: :unprocessable_entity)
            end
          rescue StandardError => e
            Rails.logger.error("[System::ProviderVolumes] Detach failed: #{e.message}")
            render_error(e.message, status: :internal_server_error)
          end

          # POST /api/v1/internal/system/provider_volumes/:id/provision
          def provision
            result = ::System::VolumeManagementService.provision(volume: @volume)

            if result[:success]
              render_success(
                data: {
                  success: true,
                  volume_id: @volume.id,
                  members_created: result[:members_created],
                  status: @volume.reload.status
                }
              )
            else
              render_error(result[:error], status: :unprocessable_entity)
            end
          rescue StandardError => e
            Rails.logger.error("[System::ProviderVolumes] Provision failed: #{e.message}")
            render_error(e.message, status: :internal_server_error)
          end

          # POST /api/v1/internal/system/provider_volumes/:id/check
          def check
            result = ::System::VolumeManagementService.check(volume: @volume)

            render_success(
              data: {
                success: result[:success],
                volume_id: @volume.id,
                actions: result[:actions],
                status: @volume.reload.status,
                error: result[:error]
              }
            )
          rescue StandardError => e
            Rails.logger.error("[System::ProviderVolumes] Check failed: #{e.message}")
            render_error(e.message, status: :internal_server_error)
          end

          # POST /api/v1/internal/system/provider_volumes/:id/recover
          def recover
            result = ::System::VolumeManagementService.recover(volume: @volume)

            if result[:success]
              render_success(
                data: {
                  success: true,
                  volume_id: @volume.id,
                  status: @volume.reload.status
                }
              )
            else
              render_error(result[:error], status: :unprocessable_entity)
            end
          rescue StandardError => e
            Rails.logger.error("[System::ProviderVolumes] Recover failed: #{e.message}")
            render_error(e.message, status: :internal_server_error)
          end

          private

          def set_volume
            @volume = ::System::ProviderVolume.find(params[:id])
          rescue ActiveRecord::RecordNotFound
            render_not_found("ProviderVolume")
          end

          def volume_data(volume)
            {
              id: volume.id,
              name: volume.name,
              description: volume.description,
              status: volume.status,
              size: volume.size,
              iops: volume.iops,
              throughput: volume.throughput,
              encrypted: volume.encrypted,
              account_id: volume.account_id,
              provider_region_id: volume.provider_region_id,
              provider_volume_type_id: volume.provider_volume_type_id,
              node_instance_id: volume.node_instance_id,
              active_instance_id: volume.active_instance_id,
              cloud_volume_id: volume.cloud_volume_id,
              device_name: volume.device_name,
              mount_point: volume.mount_point,
              raid_level: volume.raid_level,
              created_at: volume.created_at,
              updated_at: volume.updated_at
            }
          end
        end
      end
    end
  end
end
