# frozen_string_literal: true

module Api
  module V1
    # Files management controller
    # Provides endpoints for file upload, download, management across all storage providers
    class FilesController < ApplicationController
      before_action :set_file_object, only: %i[show download update destroy restore create_version add_tags remove_tags share]
      before_action :set_storage_config, only: %i[index upload]
      before_action :validate_permissions!

      # GET /api/v1/files
      def index
        files = current_account.file_objects
                               .includes(:file_storage, :file_tags, :uploaded_by)
                               .order(created_at: :desc)

        # Filter by category
        files = files.where(category: params[:category]) if params[:category].present?

        # Filter by visibility
        files = files.where(visibility: params[:visibility]) if params[:visibility].present?

        # Filter by storage
        files = files.where(file_storage_id: params[:storage_id]) if params[:storage_id].present?

        # Filter by tags
        if params[:tags].present?
          tag_names = params[:tags].split(',').map(&:strip)
          tag_ids = FileTag.where(account: current_account, name: tag_names).pluck(:id)
          files = files.joins(:file_object_tags).where(file_object_tags: { file_tag_id: tag_ids })
        end

        # Search by filename
        if params[:search].present?
          files = files.where('filename ILIKE ?', "%#{params[:search]}%")
        end

        # Exclude deleted by default unless specifically requested
        files = files.active unless params[:include_deleted] == 'true'

        # Pagination
        page = params[:page]&.to_i || 1
        per_page = [params[:per_page]&.to_i || 25, 100].min

        paginated_files = files.page(page).per(per_page)

        render_success(
          {
            files: paginated_files.map(&:file_summary),
            pagination: {
              current_page: page,
              per_page: per_page,
              total_pages: paginated_files.total_pages,
              total_count: paginated_files.total_count
            }
          }
        )
      end

      # GET /api/v1/files/:id
      def show
        file_service = FileStorageService.new(current_account, storage_config: @file_object.file_storage)

        render_success(
          {
            file: @file_object.file_summary.merge(
              urls: {
                view: file_service.file_url(@file_object),
                download: file_service.file_url(@file_object, download: true),
                signed: file_service.file_url(@file_object, signed: true, expires_in: 1.hour)
              },
              versions: @file_object.versions.map do |version|
                {
                  id: version.id,
                  version: version.version,
                  created_at: version.created_at,
                  created_by: version.created_by&.name
                }
              end,
              tags: @file_object.file_tags.map(&:tag_summary)
            )
          }
        )
      end

      # POST /api/v1/files
      def upload
        unless params[:file].present?
          return render_validation_error('File is required', field: 'file')
        end

        uploaded_file = params[:file]
        file_service = FileStorageService.new(current_account, storage_config: @storage_config)

        file_object = file_service.upload_file(
          uploaded_file,
          filename: params[:filename] || uploaded_file.original_filename,
          content_type: params[:content_type] || uploaded_file.content_type,
          category: params[:category],
          description: params[:description],
          visibility: params[:visibility] || 'private',
          metadata: params[:metadata] || {},
          uploaded_by_id: current_user&.id,
          processing_tasks: params[:processing_tasks] || []
        )

        # Add tags if provided
        if params[:tags].present?
          tag_names = params[:tags].is_a?(Array) ? params[:tags] : params[:tags].split(',')
          file_service.add_tags(file_object, tag_names)
        end

        render_success(
          {
            file: file_object.reload.file_summary,
            url: file_service.file_url(file_object)
          },
          status: :created
        )
      rescue FileStorageService::QuotaExceededError => e
        render_error(e.message, status: :unprocessable_content)
      rescue FileStorageService::InvalidFileError => e
        render_validation_error(e.message, field: 'file')
      rescue StandardError => e
        Rails.logger.error "[FilesController] Upload failed: #{e.message}"
        render_error('File upload failed', status: :internal_server_error)
      end

      # GET /api/v1/files/:id/download
      def download
        file_service = FileStorageService.new(current_account, storage_config: @file_object.file_storage)

        if params[:stream] == 'true'
          # Stream file for large files
          response.headers['Content-Type'] = @file_object.content_type
          response.headers['Content-Disposition'] = "attachment; filename=\"#{@file_object.filename}\""

          self.response_body = Enumerator.new do |yielder|
            file_service.stream_file(@file_object) do |chunk|
              yielder << chunk
            end
          end
        else
          # Direct download
          file_content = file_service.download_file(@file_object)

          send_data file_content,
                    filename: @file_object.filename,
                    type: @file_object.content_type,
                    disposition: params[:disposition] || 'attachment'
        end
      rescue FileStorageService::FileNotFoundError => e
        render_error(e.message, status: :not_found)
      rescue StandardError => e
        Rails.logger.error "[FilesController] Download failed: #{e.message}"
        render_error('File download failed', status: :internal_server_error)
      end

      # PATCH/PUT /api/v1/files/:id
      def update
        update_params = file_update_params

        if @file_object.update(update_params)
          render_success({ file: @file_object.file_summary })
        else
          render_validation_error(@file_object.errors.full_messages.join(', '))
        end
      end

      # DELETE /api/v1/files/:id
      def destroy
        file_service = FileStorageService.new(current_account, storage_config: @file_object.file_storage)
        permanent = params[:permanent] == 'true'

        if file_service.delete_file(@file_object, permanent: permanent, deleted_by_user: current_user)
          render_success(
            {
              deleted: true,
              permanent: permanent,
              message: permanent ? 'File permanently deleted' : 'File moved to trash'
            }
          )
        else
          render_error('Failed to delete file', status: :unprocessable_content)
        end
      rescue StandardError => e
        Rails.logger.error "[FilesController] Delete failed: #{e.message}"
        render_error('File deletion failed', status: :internal_server_error)
      end

      # POST /api/v1/files/:id/restore
      def restore
        file_service = FileStorageService.new(current_account, storage_config: @file_object.file_storage)

        if file_service.restore_file(@file_object)
          render_success(
            {
              file: @file_object.reload.file_summary,
              message: 'File restored successfully'
            }
          )
        else
          render_error('Failed to restore file', status: :unprocessable_content)
        end
      rescue StandardError => e
        Rails.logger.error "[FilesController] Restore failed: #{e.message}"
        render_error('File restoration failed', status: :internal_server_error)
      end

      # POST /api/v1/files/:id/versions
      def create_version
        unless params[:file].present?
          return render_validation_error('File is required', field: 'file')
        end

        file_service = FileStorageService.new(current_account, storage_config: @file_object.file_storage)

        new_version = file_service.create_version(
          @file_object,
          params[:file],
          created_by_user: current_user,
          change_description: params[:description]
        )

        render_success(
          {
            file: new_version.file_summary,
            message: 'New version created successfully'
          },
          status: :created
        )
      rescue StandardError => e
        Rails.logger.error "[FilesController] Version creation failed: #{e.message}"
        render_error('Version creation failed', status: :internal_server_error)
      end

      # POST /api/v1/files/:id/tags
      def add_tags
        unless params[:tags].present?
          return render_validation_error('Tags are required', field: 'tags')
        end

        file_service = FileStorageService.new(current_account, storage_config: @file_object.file_storage)
        tag_names = params[:tags].is_a?(Array) ? params[:tags] : params[:tags].split(',')

        tags = file_service.add_tags(@file_object, tag_names)

        render_success(
          {
            file: @file_object.reload.file_summary,
            tags: tags.map(&:tag_summary),
            message: 'Tags added successfully'
          }
        )
      rescue StandardError => e
        Rails.logger.error "[FilesController] Add tags failed: #{e.message}"
        render_error('Failed to add tags', status: :internal_server_error)
      end

      # DELETE /api/v1/files/:id/tags
      def remove_tags
        unless params[:tags].present?
          return render_validation_error('Tags are required', field: 'tags')
        end

        file_service = FileStorageService.new(current_account, storage_config: @file_object.file_storage)
        tag_names = params[:tags].is_a?(Array) ? params[:tags] : params[:tags].split(',')

        file_service.remove_tags(@file_object, tag_names)

        render_success(
          {
            file: @file_object.reload.file_summary,
            message: 'Tags removed successfully'
          }
        )
      rescue StandardError => e
        Rails.logger.error "[FilesController] Remove tags failed: #{e.message}"
        render_error('Failed to remove tags', status: :internal_server_error)
      end

      # POST /api/v1/files/:id/share
      def share
        file_service = FileStorageService.new(current_account, storage_config: @file_object.file_storage)

        file_share = file_service.create_share(
          @file_object,
          created_by_id: current_user&.id,
          expires_at: params[:expires_at] ? Time.parse(params[:expires_at]) : nil,
          max_downloads: params[:max_downloads],
          password: params[:password],
          allow_download: params[:allow_download] != false,
          require_email: params[:require_email] == true,
          notify_on_access: params[:notify_on_access] == true
        )

        render_success(
          {
            share: {
              id: file_share.id,
              share_token: file_share.share_token,
              url: file_service.share_url(file_share),
              expires_at: file_share.expires_at,
              max_downloads: file_share.max_downloads,
              download_count: file_share.download_count,
              password_protected: file_share.password_protected?
            },
            message: 'File share created successfully'
          },
          status: :created
        )
      rescue StandardError => e
        Rails.logger.error "[FilesController] Share creation failed: #{e.message}"
        render_error('Failed to create share', status: :internal_server_error)
      end

      # GET /api/v1/files/stats
      def stats
        # Get active files
        active_files = current_account.file_objects.active

        # Get category statistics
        category_stats = active_files
                          .group(:category)
                          .count
                          .transform_keys { |k| k || 'uncategorized' }

        # Get file type statistics
        type_stats = active_files
                      .group(:file_type)
                      .count
                      .transform_keys { |k| k || 'unknown' }

        # Calculate totals
        total_files = active_files.count
        total_size = active_files.sum(:file_size) || 0

        render_success(
          {
            total_files: total_files,
            total_size: total_size,
            by_category: category_stats,
            by_type: type_stats
          }
        )
      rescue StandardError => e
        Rails.logger.error "[FilesController#stats] Error: #{e.class} - #{e.message}"
        Rails.logger.error e.backtrace.first(10).join("\n")
        render_error('Failed to retrieve file statistics', status: :internal_server_error)
      end

      private

      def set_file_object
        @file_object = current_account.file_objects.find_by(id: params[:id])

        unless @file_object
          render_error('File not found', status: :not_found)
        end
      end

      def set_storage_config
        if params[:storage_id].present?
          @storage_config = current_account.file_storages.find_by(id: params[:storage_id])

          unless @storage_config
            return render_error('Storage configuration not found', status: :not_found)
          end
        else
          @storage_config = current_account.file_storages.default.first

          unless @storage_config
            return render_error('No default storage configuration found', status: :not_found)
          end
        end
      end

      def validate_permissions!
        case action_name
        when 'index', 'show', 'download', 'stats'
          require_permission('files.read')
        when 'upload'
          require_permission('files.create')
        when 'update', 'create_version', 'add_tags', 'remove_tags', 'share'
          require_permission('files.update')
        when 'destroy', 'restore'
          require_permission('files.delete')
        end
      end

      def file_update_params
        params.permit(:filename, :description, :visibility, :category, metadata: {})
      end
    end
  end
end
