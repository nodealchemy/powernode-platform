# frozen_string_literal: true

module Api
  module V1
    module System
      module WorkerApi
        # Module data and file management for infrastructure workers
        # Provides module configuration and data file transfers
        class ModulesController < BaseController
          before_action :set_module, only: [:show, :download, :upload, :versions, :rollback]

          # GET /api/v1/system/worker_api/modules
          # List modules for nodes managed by this worker
          def index
            authorize_worker_permission!("system.modules.read")

            # Get modules assigned to nodes managed by this worker
            node_ids = ::System::Node.where(worker: current_worker).pluck(:id)
            module_ids = ::System::NodeModuleAssignment.where(node_id: node_ids).pluck(:node_module_id).uniq

            modules = ::System::NodeModule.where(id: module_ids)
            modules = apply_filters(modules)
            modules = paginate(modules.includes(:category, :node_platform))

            render_success(
              modules: modules.map { |m| serialize_module(m) },
              meta: pagination_meta
            )
          end

          # GET /api/v1/system/worker_api/modules/:id
          def show
            authorize_worker_permission!("system.modules.read")
            render_success(module: serialize_module_full(@module))
          end

          # GET /api/v1/system/worker_api/modules/:id/download
          # Download module data file
          def download
            authorize_worker_permission!("system.modules.read")

            unless @module.data_file_name.present?
              return render_error("Module has no data file")
            end

            # In a real implementation, this would stream the actual file
            # For now, return file metadata for the worker to fetch
            render_success(
              file: {
                name: @module.data_file_name,
                size: @module.data_file_size,
                checksum: @module.data_checksum,
                download_url: module_download_url(@module)
              }
            )
          end

          # POST /api/v1/system/worker_api/modules/:id/upload
          # Upload module data file (for module transfer operations)
          def upload
            authorize_worker_permission!("system.modules.update")

            if @module.locked?
              return render_error("Module is locked and cannot be modified")
            end

            filename = params[:filename]
            checksum = params[:checksum]
            size = params[:size].to_i

            unless filename.present? && checksum.present? && size > 0
              return render_error("filename, checksum, and size are required")
            end

            @module.update!(
              data_file_name: filename,
              data_checksum: checksum,
              data_file_size: size
            )

            render_success(
              module: serialize_module(@module),
              upload_accepted: true
            )
          end

          # GET /api/v1/system/worker_api/modules/:id/versions
          # List module versions
          def versions
            authorize_worker_permission!("system.modules.read")

            versions = @module.versions.ordered.limit(params[:limit] || 20)

            render_success(
              versions: versions.map { |v| serialize_version(v) },
              current_version: @module.current_version_number
            )
          end

          # POST /api/v1/system/worker_api/modules/:id/rollback
          # Rollback module to specific version
          def rollback
            authorize_worker_permission!("system.modules.update")

            version_number = params[:version_number].to_i
            version = @module.version(version_number)

            unless version
              return render_error("Version #{version_number} not found")
            end

            begin
              new_version = @module.rollback_to!(version, changelog: "Rollback initiated by worker")

              render_success(
                module: serialize_module(@module.reload),
                rolled_back_to: version_number,
                new_version: new_version.version_number
              )
            rescue ::System::ModuleVersionService::LockError => e
              render_error(e.message)
            rescue ::System::ModuleVersionService::RollbackError => e
              render_error(e.message)
            end
          end

          # GET /api/v1/system/worker_api/modules/for_node/:node_id
          # Get all modules for a specific node with dependencies resolved
          def for_node
            authorize_worker_permission!("system.modules.read")

            node = ::System::Node.where(worker: current_worker).find(params[:node_id])
            modules = node.node_modules.enabled.includes(:category, :dependencies)

            # Resolve dependencies
            resolved_modules = resolve_module_dependencies(modules)

            render_success(
              node_id: node.id,
              modules: resolved_modules.map { |m| serialize_module_with_order(m) }
            )
          rescue ActiveRecord::RecordNotFound
            render_record_not_found("Node")
          end

          private

          def set_module
            # Get modules that are assigned to nodes managed by this worker
            node_ids = ::System::Node.where(worker: current_worker).pluck(:id)
            module_ids = ::System::NodeModuleAssignment.where(node_id: node_ids).pluck(:node_module_id).uniq

            @module = ::System::NodeModule.where(id: module_ids).find(params[:id])
          rescue ActiveRecord::RecordNotFound
            render_record_not_found("NodeModule")
          end

          def apply_filters(scope)
            scope = scope.enabled if params[:enabled] == "true"
            scope = scope.by_variety(params[:variety]) if params[:variety].present?
            scope = scope.in_category(params[:category_id]) if params[:category_id].present?
            scope.by_priority
          end

          def resolve_module_dependencies(modules)
            # Simple topological sort based on dependencies
            resolved = []
            visited = Set.new
            temp_visited = Set.new

            modules.each do |mod|
              visit_module(mod, modules, resolved, visited, temp_visited)
            end

            resolved
          end

          def visit_module(mod, available_modules, resolved, visited, temp_visited)
            return if visited.include?(mod.id)

            if temp_visited.include?(mod.id)
              # Circular dependency detected, skip but log
              Rails.logger.warn "Circular dependency detected for module #{mod.id}"
              return
            end

            temp_visited.add(mod.id)

            mod.dependencies.each do |dep|
              if available_modules.include?(dep)
                visit_module(dep, available_modules, resolved, visited, temp_visited)
              end
            end

            temp_visited.delete(mod.id)
            visited.add(mod.id)
            resolved << mod
          end

          def module_download_url(mod)
            # Generate a signed URL for file download
            # This is a placeholder - actual implementation depends on storage backend
            "/api/v1/system/worker_api/files/modules/#{mod.id}/#{mod.data_file_name}"
          end

          def serialize_module(mod)
            {
              id: mod.id,
              name: mod.name,
              variety: mod.variety,
              enabled: mod.enabled,
              priority: mod.priority,
              category_id: mod.category_id,
              platform_id: mod.node_platform_id,
              has_data_file: mod.data_file_name.present?,
              current_version: mod.current_version_number,
              locked: mod.locked?,
              created_at: mod.created_at,
              updated_at: mod.updated_at
            }
          end

          def serialize_module_full(mod)
            serialize_module(mod).merge(
              description: mod.description,
              mask: mod.mask,
              file_spec: mod.file_spec,
              package_spec: mod.package_spec,
              config: mod.config,
              data_file_name: mod.data_file_name,
              data_file_size: mod.data_file_size,
              data_checksum: mod.data_checksum,
              dependencies: mod.dependencies.map { |d| { id: d.id, name: d.name } },
              puppet_modules: mod.puppet_modules.enabled.map { |p| { id: p.id, name: p.name } }
            )
          end

          def serialize_module_with_order(mod)
            serialize_module(mod).merge(
              dependencies: mod.dependencies.map(&:id)
            )
          end

          def serialize_version(version)
            {
              id: version.id,
              version_number: version.version_number,
              changelog: version.changelog,
              has_data_file: version.has_data_file?,
              data_checksum: version.data_checksum,
              is_current: version.current?,
              created_at: version.created_at
            }
          end
        end
      end
    end
  end
end
