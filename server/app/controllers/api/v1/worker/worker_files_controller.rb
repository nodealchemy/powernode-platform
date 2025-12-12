# frozen_string_literal: true

module Api
  module V1
    module Worker
      # Controller for worker file processing operations
      # Provides API endpoints for workers to download files, upload results, and update metadata
      class WorkerFilesController < WorkerBaseController
        before_action :set_file_object, only: %i[show download update processed]

        # GET /api/v1/worker/files/:id
        def show
          render_success({
            id: @file_object.id,
            filename: @file_object.filename,
            content_type: @file_object.content_type,
            file_type: @file_object.file_type,
            file_size: @file_object.file_size,
            storage_key: @file_object.storage_key,
            metadata: @file_object.metadata,
            processing_status: @file_object.processing_status,
            file_object_id: @file_object.id
          })
        end

        # GET /api/v1/worker/files/:id/download
        def download
          file_service = FileStorageService.new(@file_object.account, storage_config: @file_object.file_storage)

          # Download file content
          file_content = file_service.download_file(@file_object)

          # Send binary data
          send_data file_content,
                    filename: @file_object.filename,
                    type: @file_object.content_type,
                    disposition: "attachment"

        rescue FileStorageService::FileNotFoundError => e
          render_error(e.message, status: :not_found)
        rescue StandardError => e
          Rails.logger.error "[WorkerFilesController] Download failed: #{e.message}"
          render_error("File download failed", status: :internal_server_error)
        end

        # PATCH /api/v1/worker/files/:id
        def update
          update_params = params.permit(:processing_status, metadata: {}, exif_data: {}, dimensions: {})

          # Merge metadata instead of replacing
          if update_params[:metadata]
            update_params[:metadata] = @file_object.metadata.merge(update_params[:metadata].to_unsafe_h)
          end

          if update_params[:exif_data]
            update_params[:exif_data] = @file_object.exif_data.merge(update_params[:exif_data].to_unsafe_h)
          end

          if update_params[:dimensions]
            update_params[:dimensions] = @file_object.dimensions.merge(update_params[:dimensions].to_unsafe_h)
          end

          if @file_object.update(update_params)
            render_success({ file: @file_object.file_summary })
          else
            render_validation_error(@file_object.errors.full_messages.join(", "))
          end

        rescue StandardError => e
          Rails.logger.error "[WorkerFilesController] Update failed: #{e.message}"
          render_error("File update failed", status: :internal_server_error)
        end

        # POST /api/v1/worker/files/:id/processed
        # Uploads processed file results (thumbnails, transcoded versions, etc.)
        def processed
          unless params[:file_content]
            return render_validation_error("file_content is required", field: "file_content")
          end

          # Decode base64 file content
          file_content = Base64.strict_decode64(params[:file_content])

          # Get metadata
          metadata = params[:metadata] || {}
          storage_key = metadata["storage_key"] || "processed/#{@file_object.id}/#{SecureRandom.hex(8)}"

          # Upload to storage
          file_service = FileStorageService.new(@file_object.account, storage_config: @file_object.file_storage)

          # Create temp file
          temp_file = Tempfile.new([ "processed", ".tmp" ], binmode: true)
          temp_file.write(file_content)
          temp_file.rewind

          # Upload via provider
          provider = @file_object.file_storage.storage_provider
          provider.upload_file_to_key(temp_file, storage_key)

          temp_file.close
          temp_file.unlink

          # Update file metadata with processed file reference
          processed_files = @file_object.metadata["processed_files"] || []
          processed_files << {
            type: metadata["type"],
            size: metadata["size"],
            storage_key: storage_key,
            created_at: Time.current.iso8601
          }

          @file_object.update!(metadata: @file_object.metadata.merge("processed_files" => processed_files))

          render_success(
            {
              message: "Processed file uploaded successfully",
              storage_key: storage_key,
              file: @file_object.file_summary
            },
            status: :created
          )

        rescue ArgumentError => e
          render_validation_error("Invalid base64 file_content", field: "file_content")
        rescue StandardError => e
          Rails.logger.error "[WorkerFilesController] Processed file upload failed: #{e.message}"
          render_error("Failed to upload processed file", status: :internal_server_error)
        end

        private

        def set_file_object
          @file_object = FileObject.find_by(id: params[:id])

          unless @file_object
            render_error("File not found", status: :not_found)
          end
        end
      end
    end
  end
end
