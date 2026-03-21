# frozen_string_literal: true

module Api
  module V1
    module Internal
      module System
        # Internal API controller for system node instance operations
        # Handles SSH execution, lifecycle control, and IP management
        class NodeInstancesController < BaseController
          before_action :set_instance, except: %i[index create]

          # GET /api/v1/internal/system/node_instances
          def index
            instances = ::System::NodeInstance.all

            instances = instances.where(node_id: params[:node_id]) if params[:node_id].present?
            instances = instances.where(variety: Array(params[:variety])) if params[:variety].present?
            instances = instances.where(status: params[:status]) if params[:status].present?

            if params[:for_health_check].present?
              instances = instances.where(status: %w[running starting stopping])
            end

            instances = instances.includes(:node, :provider_region)
                                 .limit(params[:limit] || 100)

            render_success(
              data: {
                node_instances: instances.map { |i| instance_data(i) }
              }
            )
          end

          # GET /api/v1/internal/system/node_instances/:id
          def show
            render_success(data: instance_data(@instance))
          end

          # POST /api/v1/internal/system/node_instances/:id/start
          def start
            result = control_instance(:start)
            render_control_result(result, "start")
          end

          # POST /api/v1/internal/system/node_instances/:id/stop
          def stop
            result = control_instance(:stop)
            render_control_result(result, "stop")
          end

          # POST /api/v1/internal/system/node_instances/:id/reboot
          def reboot
            result = control_instance(:reboot)
            render_control_result(result, "reboot")
          end

          # POST /api/v1/internal/system/node_instances/:id/terminate
          def terminate
            result = control_instance(:terminate)
            render_control_result(result, "terminate")
          end

          # POST /api/v1/internal/system/node_instances/:id/ssh_exec
          # Execute command via SSH on the instance
          def ssh_exec
            command = params[:command]
            sudo = params[:sudo] != false
            operation_id = params[:operation_id]

            unless command.present?
              return render_error("Command is required", status: :unprocessable_entity)
            end

            result = ::System::SshExecutionService.execute(
              instance: @instance,
              command: command,
              sudo: sudo,
              operation_id: operation_id
            )

            render_success(
              data: {
                success: result[:success],
                stdout: result[:stdout],
                stderr: result[:stderr],
                exit_code: result[:exit_code],
                error: result[:error]
              }
            )
          rescue StandardError => e
            Rails.logger.error("[System::NodeInstances] SSH exec failed: #{e.message}")
            render_error(e.message, status: :internal_server_error)
          end

          # POST /api/v1/internal/system/node_instances/:id/ssh_sync
          # Sync instance state via SSH
          def ssh_sync
            result = ::System::SshExecutionService.sync(instance: @instance)

            @instance.update(last_synced_at: Time.current) if result[:success]

            render_success(
              data: {
                success: result[:success],
                error: result[:error]
              }
            )
          rescue StandardError => e
            Rails.logger.error("[System::NodeInstances] SSH sync failed: #{e.message}")
            render_error(e.message, status: :internal_server_error)
          end

          # POST /api/v1/internal/system/node_instances/:id/ssh_cleanse
          # Cleanse instance configuration via SSH
          def ssh_cleanse
            result = ::System::SshExecutionService.cleanse(instance: @instance)

            render_success(
              data: {
                success: result[:success],
                error: result[:error]
              }
            )
          rescue StandardError => e
            Rails.logger.error("[System::NodeInstances] SSH cleanse failed: #{e.message}")
            render_error(e.message, status: :internal_server_error)
          end

          # POST /api/v1/internal/system/node_instances/:id/associate_public_ip
          def associate_public_ip
            result = ::System::IpManagementService.associate_public_ip(instance: @instance)

            if result[:success]
              render_success(
                data: {
                  success: true,
                  public_ip_address: result[:public_ip_address]
                }
              )
            else
              render_error(result[:error], status: :unprocessable_entity)
            end
          rescue StandardError => e
            Rails.logger.error("[System::NodeInstances] Associate IP failed: #{e.message}")
            render_error(e.message, status: :internal_server_error)
          end

          # POST /api/v1/internal/system/node_instances/:id/disassociate_public_ip
          def disassociate_public_ip
            result = ::System::IpManagementService.disassociate_public_ip(instance: @instance)

            if result[:success]
              render_success(data: { success: true })
            else
              render_error(result[:error], status: :unprocessable_entity)
            end
          rescue StandardError => e
            Rails.logger.error("[System::NodeInstances] Disassociate IP failed: #{e.message}")
            render_error(e.message, status: :internal_server_error)
          end

          # POST /api/v1/internal/system/node_instances/:id/create_image
          # Create bootable image from instance
          def create_image
            image_format = params[:image_format] || "img"
            operation_id = params[:operation_id]

            unless %w[img iso].include?(image_format)
              return render_error("Invalid image format", status: :unprocessable_entity)
            end

            result = ::System::ImageCreationService.create_instance_image(
              instance: @instance,
              format: image_format,
              operation_id: operation_id
            )

            if result[:success]
              render_success(
                data: {
                  success: true,
                  image_path: result[:image_path],
                  image_size: result[:image_size]
                }
              )
            else
              render_error(result[:error], status: :unprocessable_entity)
            end
          rescue StandardError => e
            Rails.logger.error("[System::NodeInstances] Create image failed: #{e.message}")
            render_error(e.message, status: :internal_server_error)
          end

          # POST /api/v1/internal/system/node_instances/:id/maintenance
          # Run maintenance on instance
          def maintenance
            result = ::System::InstanceMaintenanceService.run_maintenance(instance: @instance)

            render_success(
              data: {
                success: result[:success],
                actions_taken: result[:actions_taken],
                error: result[:error]
              }
            )
          rescue StandardError => e
            Rails.logger.error("[System::NodeInstances] Maintenance failed: #{e.message}")
            render_error(e.message, status: :internal_server_error)
          end

          # POST /api/v1/internal/system/node_instances/:id/sync_cloud_state
          # Sync instance state from cloud provider
          def sync_cloud_state
            result = ::System::CloudSyncService.sync_instance_state(instance: @instance)

            if result[:success]
              @instance.update!(
                status: result[:status],
                private_ip_address: result[:private_ip_address],
                public_ip_address: result[:public_ip_address],
                last_synced_at: Time.current
              )

              render_success(
                data: {
                  success: true,
                  status: result[:status],
                  private_ip_address: result[:private_ip_address],
                  public_ip_address: result[:public_ip_address],
                  updated: result[:updated]
                }
              )
            else
              render_error(result[:error], status: :unprocessable_entity)
            end
          rescue StandardError => e
            Rails.logger.error("[System::NodeInstances] Cloud state sync failed: #{e.message}")
            render_error(e.message, status: :internal_server_error)
          end

          # POST /api/v1/internal/system/node_instances/:id/sync_netboot
          # Sync netboot configuration for physical instances
          def sync_netboot
            unless @instance.variety == "physical"
              return render_error("Netboot sync only available for physical instances", status: :unprocessable_entity)
            end

            result = ::System::NetbootService.sync(instance: @instance)

            if result[:success]
              render_success(data: { success: true })
            else
              render_error(result[:error], status: :unprocessable_entity)
            end
          rescue StandardError => e
            Rails.logger.error("[System::NodeInstances] Netboot sync failed: #{e.message}")
            render_error(e.message, status: :internal_server_error)
          end

          # DELETE /api/v1/internal/system/node_instances/:id
          # Destroy an instance record (for terminated instances cleanup)
          def destroy
            unless @instance.status == "terminated"
              return render_error("Can only delete terminated instances", status: :unprocessable_entity)
            end

            @instance.destroy!
            render_success(data: { success: true, message: "Instance deleted" })
          rescue StandardError => e
            Rails.logger.error("[System::NodeInstances] Destroy failed: #{e.message}")
            render_error(e.message, status: :internal_server_error)
          end

          private

          def set_instance
            @instance = ::System::NodeInstance.find(params[:id])
          rescue ActiveRecord::RecordNotFound
            render_not_found("NodeInstance")
          end

          def control_instance(action)
            ::System::InstanceControlService.execute(
              instance: @instance,
              action: action,
              operation_id: params[:operation_id]
            )
          end

          def render_control_result(result, action)
            if result[:success]
              render_success(
                data: {
                  success: true,
                  instance_id: @instance.id,
                  action: action,
                  new_status: @instance.reload.status
                }
              )
            else
              render_error(result[:error], status: :unprocessable_entity)
            end
          end

          def instance_data(instance)
            node = instance.node
            {
              id: instance.id,
              name: instance.name,
              variety: instance.variety,
              status: instance.status,
              node_id: instance.node_id,
              node: node ? { id: node.id, name: node.name, enabled: node.enabled } : nil,
              private_ip_address: instance.private_ip_address,
              public_ip_address: instance.public_ip_address,
              vpn_ip_address: instance.vpn_ip_address,
              provider_region_id: instance.provider_region_id,
              provider_instance_type_id: instance.provider_instance_type_id,
              cloud_instance_id: instance.cloud_instance_id,
              admin_user: instance.admin_user,
              ssh_ip_address: instance.ssh_ip_address,
              ssh_key: instance.key.present?,
              last_synced_at: instance.last_synced_at,
              created_at: instance.created_at,
              updated_at: instance.updated_at
            }
          end
        end
      end
    end
  end
end
