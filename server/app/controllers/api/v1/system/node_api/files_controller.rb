# frozen_string_literal: true

module Api
  module V1
    module System
      module NodeApi
        # File download endpoint for node instances
        # Provides access to module data files and other resources
        class FilesController < BaseController
          # GET /api/v1/system/node_api/files/modules/:module_id/:filename
          # Download module data file
          def module_file
            node_module = node_modules.find(params[:module_id])
            filename = params[:filename]

            unless node_module.data_file_name == filename
              return render_not_found("File")
            end

            # In a real implementation, this would stream the actual file
            # from storage (S3, local filesystem, etc.)
            # For now, return file metadata
            render_success(
              file: {
                id: node_module.id,
                name: filename,
                size: node_module.data_file_size,
                checksum: node_module.data_checksum,
                content_type: detect_content_type(filename)
              },
              message: "File streaming not implemented - use storage URL directly"
            )
          rescue ActiveRecord::RecordNotFound
            render_record_not_found("NodeModule")
          end

          # GET /api/v1/system/node_api/files/scripts/:script_id
          # Download script file
          def script_file
            script = node_scripts.find(params[:script_id])

            render_success(
              file: {
                id: script.id,
                name: "#{script.name}.#{script_extension(script.interpreter)}",
                content: script.content,
                checksum: Digest::SHA256.hexdigest(script.content || ""),
                content_type: "text/plain"
              }
            )
          rescue ActiveRecord::RecordNotFound
            render_record_not_found("Script")
          end

          private

          def node_modules
            module_ids = ::System::NodeModuleAssignment
                         .where(node_id: current_node.id, enabled: true)
                         .pluck(:node_module_id)

            ::System::NodeModule.where(id: module_ids)
          end

          def node_scripts
            template = current_node.node_template

            if template&.respond_to?(:scripts)
              template.scripts
            else
              ::System::NodeScript.where(account_id: current_account.id)
            end
          end

          def detect_content_type(filename)
            extension = File.extname(filename).downcase

            case extension
            when ".tar", ".tar.gz", ".tgz"
              "application/x-tar"
            when ".gz"
              "application/gzip"
            when ".zip"
              "application/zip"
            when ".json"
              "application/json"
            when ".yaml", ".yml"
              "application/x-yaml"
            when ".sh"
              "application/x-sh"
            when ".rb"
              "application/x-ruby"
            when ".py"
              "application/x-python"
            else
              "application/octet-stream"
            end
          end

          def script_extension(interpreter)
            case interpreter
            when /bash|sh/i
              "sh"
            when /ruby/i
              "rb"
            when /python/i
              "py"
            when /perl/i
              "pl"
            else
              "sh"
            end
          end
        end
      end
    end
  end
end
