# frozen_string_literal: true

module Api
  module V1
    module System
      module NodeApi
        # Module data endpoint for node instances
        # Provides modules assigned to the instance's node
        class ModulesController < BaseController
          before_action :set_module, only: [:show, :download, :resource]

          # GET /api/v1/system/node_api/modules
          # List modules assigned to this node with dependencies resolved
          def index
            modules = node_modules.enabled.includes(:category, :dependencies)
            resolved_modules = resolve_module_dependencies(modules)

            render_success(
              modules: resolved_modules.map { |m| serialize_module(m) },
              count: resolved_modules.size
            )
          end

          # GET /api/v1/system/node_api/modules/:id
          # Get specific module details
          def show
            render_success(module: serialize_module_full(@module))
          end

          # GET /api/v1/system/node_api/modules/:id/download
          # Get module data file download info
          def download
            unless @module.data_file_name.present?
              return render_error("Module has no data file")
            end

            render_success(
              file: {
                name: @module.data_file_name,
                size: @module.data_file_size,
                checksum: @module.data_checksum,
                download_url: module_download_url(@module)
              }
            )
          end

          # GET /api/v1/system/node_api/modules/:id/:resource
          # Get specific module resource
          def resource
            resource_name = params[:resource]

            # Check if module has the requested resource
            resource_data = @module.config&.dig("resources", resource_name)

            if resource_data.blank?
              return render_not_found("ModuleResource")
            end

            render_success(
              module_id: @module.id,
              resource: resource_name,
              data: resource_data
            )
          end

          private

          def set_module
            @module = node_modules.find(params[:id])
          rescue ActiveRecord::RecordNotFound
            render_record_not_found("NodeModule")
          end

          def node_modules
            # Get modules assigned to this node
            module_ids = ::System::NodeModuleAssignment
                         .where(node_id: current_node.id, enabled: true)
                         .pluck(:node_module_id)

            ::System::NodeModule.where(id: module_ids)
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
              if available_modules.map(&:id).include?(dep.id)
                visit_module(dep, available_modules, resolved, visited, temp_visited)
              end
            end

            temp_visited.delete(mod.id)
            visited.add(mod.id)
            resolved << mod
          end

          def module_download_url(mod)
            # Generate URL for file download
            "/api/v1/system/node_api/files/modules/#{mod.id}/#{mod.data_file_name}"
          end

          def serialize_module(mod)
            {
              id: mod.id,
              name: mod.name,
              variety: mod.variety,
              priority: mod.priority,
              category_id: mod.category_id,
              has_data_file: mod.data_file_name.present?,
              current_version: mod.current_version_number,
              dependencies: mod.dependencies.map(&:id)
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
              puppet_modules: mod.puppet_modules.enabled.map { |p| { id: p.id, name: p.name } }
            )
          end
        end
      end
    end
  end
end
