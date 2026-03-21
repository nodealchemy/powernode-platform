# frozen_string_literal: true

module Api
  module V1
    module Internal
      module System
        # Internal API controller for system node architecture operations
        class NodeArchitecturesController < BaseController
          before_action :set_architecture, only: %i[show create_image]

          # GET /api/v1/internal/system/node_architectures/:id
          def show
            render_success(data: architecture_data(@architecture))
          end

          # POST /api/v1/internal/system/node_architectures/:id/create_image
          # Create bootable image from architecture
          def create_image
            image_format = params[:image_format] || "img"
            operation_id = params[:operation_id]

            unless %w[img iso].include?(image_format)
              return render_error("Invalid image format", status: :unprocessable_entity)
            end

            result = ::System::ImageCreationService.create_architecture_image(
              architecture: @architecture,
              format: image_format,
              operation_id: operation_id
            )

            if result[:success]
              render_success(
                data: {
                  success: true,
                  architecture_id: @architecture.id,
                  image_path: result[:image_path],
                  image_size: result[:image_size]
                }
              )
            else
              render_error(result[:error], status: :unprocessable_entity)
            end
          rescue StandardError => e
            Rails.logger.error("[System::NodeArchitectures] Create image failed: #{e.message}")
            render_error(e.message, status: :internal_server_error)
          end

          private

          def set_architecture
            @architecture = ::System::NodeArchitecture.find(params[:id])
          rescue ActiveRecord::RecordNotFound
            render_not_found("NodeArchitecture")
          end

          def architecture_data(architecture)
            {
              id: architecture.id,
              name: architecture.name,
              description: architecture.description,
              enabled: architecture.enabled,
              public: architecture.public,
              kernel_options: architecture.kernel_options,
              kernel_checksum: architecture.kernel_checksum,
              ramdisk_checksum: architecture.ramdisk_checksum,
              image_checksum: architecture.image_checksum,
              account_id: architecture.account_id,
              created_at: architecture.created_at,
              updated_at: architecture.updated_at
            }
          end
        end
      end
    end
  end
end
