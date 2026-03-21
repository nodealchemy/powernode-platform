# frozen_string_literal: true

module Api
  module V1
    module System
      class ProviderVolumesController < BaseController
        before_action :set_volume, only: [:show, :update, :destroy, :attach, :detach, :snapshot]

        # GET /api/v1/system/provider_volumes
        def index
          authorize_permission!('system.volumes.read')

          volumes = current_account.system_provider_volumes
          volumes = apply_filters(volumes)
          volumes = paginate(volumes.includes(:volume_type, :provider_region, :node_instance).by_name)

          render_success(
            volumes: volumes.map { |v| ::System::ProviderVolumeSerializer.new(v).as_json },
            meta: pagination_meta
          )
        end

        # GET /api/v1/system/provider_volumes/:id
        def show
          authorize_permission!('system.volumes.read')
          render_success(volume: ::System::ProviderVolumeSerializer.new(@volume).as_json)
        end

        # POST /api/v1/system/provider_volumes
        def create
          authorize_permission!('system.volumes.create')

          volume = current_account.system_provider_volumes.build(volume_params)

          if volume.save
            render_success(volume: ::System::ProviderVolumeSerializer.new(volume).as_json, status: :created)
          else
            render_validation_error(volume)
          end
        end

        # PATCH/PUT /api/v1/system/provider_volumes/:id
        def update
          authorize_permission!('system.volumes.update')

          if @volume.update(volume_params)
            render_success(volume: ::System::ProviderVolumeSerializer.new(@volume).as_json)
          else
            render_validation_error(@volume)
          end
        end

        # DELETE /api/v1/system/provider_volumes/:id
        def destroy
          authorize_permission!('system.volumes.delete')

          unless @volume.can_delete?
            return render_error('Cannot delete volume in current state', status: :unprocessable_entity)
          end

          @volume.update!(status: 'deleting')
          render_success(message: 'Volume deletion initiated')
        end

        # POST /api/v1/system/provider_volumes/:id/attach
        def attach
          authorize_permission!('system.volumes.update')

          instance = current_account.system_nodes
                                   .flat_map(&:node_instances)
                                   .find { |i| i.id == params[:node_instance_id] }

          unless instance
            return render_error('Node instance not found', status: :not_found)
          end

          if @volume.attach_to!(instance, params[:device_name])
            render_success(volume: ::System::ProviderVolumeSerializer.new(@volume.reload).as_json)
          else
            render_error('Cannot attach volume in current state', status: :unprocessable_entity)
          end
        end

        # POST /api/v1/system/provider_volumes/:id/detach
        def detach
          authorize_permission!('system.volumes.update')

          if @volume.detach!
            render_success(volume: ::System::ProviderVolumeSerializer.new(@volume.reload).as_json)
          else
            render_error('Cannot detach volume in current state', status: :unprocessable_entity)
          end
        end

        # POST /api/v1/system/provider_volumes/:id/snapshot
        def snapshot
          authorize_permission!('system.volumes.snapshot')

          unless @volume.can_snapshot?
            return render_error('Cannot create snapshot in current state', status: :unprocessable_entity)
          end

          snap = current_account.system_provider_volume_snapshots.create!(
            name: params[:name] || "#{@volume.name}-snapshot-#{Time.current.strftime('%Y%m%d%H%M%S')}",
            description: params[:description],
            volume: @volume,
            size_gb: @volume.size_gb,
            encrypted: @volume.encrypted,
            status: 'pending'
          )

          render_success(snapshot: ::System::ProviderVolumeSnapshotSerializer.new(snap).as_json, status: :created)
        end

        private

        def set_volume
          @volume = current_account.system_provider_volumes.find(params[:id])
        end

        def volume_params
          params.require(:volume).permit(
            :name, :description, :size_gb, :iops, :throughput,
            :device_name, :encrypted, :delete_on_termination,
            :volume_type_id, :provider_region_id, :availability_zone_id,
            config: {}
          )
        end

        def apply_filters(volumes)
          volumes = volumes.by_status(params[:status]) if params[:status].present?
          volumes = volumes.attached if params[:attached] == 'true'
          volumes = volumes.unattached if params[:attached] == 'false'
          volumes = volumes.encrypted_volumes if params[:encrypted] == 'true'
          volumes = volumes.where('name ILIKE ?', "%#{params[:search]}%") if params[:search].present?
          volumes
        end
      end
    end
  end
end
