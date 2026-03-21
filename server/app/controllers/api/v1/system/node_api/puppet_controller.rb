# frozen_string_literal: true

module Api
  module V1
    module System
      module NodeApi
        # Puppet resources endpoint for node instances
        # Provides puppet module and resource configuration
        class PuppetController < BaseController
          # GET /api/v1/system/node_api/puppet/resources
          # Get all puppet resources for this instance
          def resources
            puppet_modules = node_puppet_modules.enabled.includes(:puppet_resources)
            resources = puppet_modules.flat_map(&:puppet_resources)

            render_success(
              resources: resources.map { |r| serialize_resource(r) },
              modules: puppet_modules.map { |m| serialize_puppet_module(m) },
              count: resources.size
            )
          end

          # GET /api/v1/system/node_api/puppet/modules
          # Get puppet modules for this instance
          def modules
            puppet_modules = node_puppet_modules.enabled.ordered

            render_success(
              modules: puppet_modules.map { |m| serialize_puppet_module_full(m) },
              count: puppet_modules.size
            )
          end

          # GET /api/v1/system/node_api/puppet/modules/:id
          # Get specific puppet module details
          def show_module
            puppet_module = node_puppet_modules.find(params[:id])

            render_success(
              module: serialize_puppet_module_full(puppet_module),
              resources: puppet_module.puppet_resources.map { |r| serialize_resource(r) }
            )
          rescue ActiveRecord::RecordNotFound
            render_record_not_found("PuppetModule")
          end

          # GET /api/v1/system/node_api/puppet/manifest
          # Generate puppet manifest for this instance
          def manifest
            puppet_modules = node_puppet_modules.enabled.ordered
            resources = puppet_modules.flat_map(&:puppet_resources)

            manifest_content = generate_manifest(puppet_modules, resources)

            render_success(
              manifest: manifest_content,
              modules_count: puppet_modules.size,
              resources_count: resources.size
            )
          end

          private

          def node_puppet_modules
            # Get puppet modules through node modules
            node_module_ids = ::System::NodeModuleAssignment
                              .where(node_id: current_node.id, enabled: true)
                              .pluck(:node_module_id)

            puppet_module_ids = ::System::ModulePuppetAssignment
                                .where(node_module_id: node_module_ids)
                                .pluck(:puppet_module_id)

            ::System::PuppetModule.where(id: puppet_module_ids)
          end

          def serialize_resource(resource)
            {
              id: resource.id,
              name: resource.name,
              resource_type: resource.resource_type,
              title: resource.title,
              parameters: resource.parameters,
              ensure_state: resource.ensure_state,
              order: resource.order
            }
          end

          def serialize_puppet_module(mod)
            {
              id: mod.id,
              name: mod.name,
              version: mod.version,
              enabled: mod.enabled
            }
          end

          def serialize_puppet_module_full(mod)
            serialize_puppet_module(mod).merge(
              source: mod.source,
              author: mod.author,
              description: mod.description,
              config: mod.config,
              resources_count: mod.puppet_resources.count
            )
          end

          def generate_manifest(puppet_modules, resources)
            lines = []
            lines << "# Puppet manifest for instance: #{current_instance.name}"
            lines << "# Generated at: #{Time.current.iso8601}"
            lines << ""

            # Add module includes
            puppet_modules.each do |mod|
              lines << "# Module: #{mod.name} (#{mod.version})"
            end
            lines << ""

            # Add resources
            resources.sort_by(&:order).each do |resource|
              lines << generate_resource_block(resource)
              lines << ""
            end

            lines.join("\n")
          end

          def generate_resource_block(resource)
            params = resource.parameters || {}
            params["ensure"] = resource.ensure_state if resource.ensure_state.present?

            block = "#{resource.resource_type} { '#{resource.title}':\n"
            params.each do |key, value|
              formatted_value = format_puppet_value(value)
              block += "  #{key} => #{formatted_value},\n"
            end
            block += "}"
            block
          end

          def format_puppet_value(value)
            case value
            when String
              "'#{value}'"
            when TrueClass, FalseClass
              value.to_s
            when Array
              "[#{value.map { |v| format_puppet_value(v) }.join(', ')}]"
            when Hash
              "{ #{value.map { |k, v| "#{k} => #{format_puppet_value(v)}" }.join(', ')} }"
            else
              value.to_s
            end
          end
        end
      end
    end
  end
end
