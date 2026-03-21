# frozen_string_literal: true

module Api
  module V1
    module System
      module NodeApi
        # Script content endpoint for node instances
        # Provides scripts assigned to the instance's node
        class ScriptsController < BaseController
          before_action :set_script, only: [:show, :content]

          # GET /api/v1/system/node_api/scripts
          # List scripts available to this instance
          def index
            scripts = node_scripts.ordered

            render_success(
              scripts: scripts.map { |s| serialize_script(s) },
              count: scripts.size
            )
          end

          # GET /api/v1/system/node_api/scripts/:id
          # Get specific script details
          def show
            render_success(script: serialize_script_full(@script))
          end

          # GET /api/v1/system/node_api/scripts/:id/content
          # Get script content for execution
          def content
            render_success(
              id: @script.id,
              name: @script.name,
              content: @script.content,
              interpreter: @script.interpreter,
              checksum: calculate_checksum(@script.content)
            )
          end

          private

          def set_script
            @script = node_scripts.find(params[:id])
          rescue ActiveRecord::RecordNotFound
            render_record_not_found("Script")
          end

          def node_scripts
            # Get scripts from template or directly assigned to node
            template = current_node.node_template

            if template&.respond_to?(:scripts)
              template.scripts
            else
              # Fallback to account-level scripts
              ::System::NodeScript.where(account_id: current_account.id)
            end
          end

          def serialize_script(script)
            {
              id: script.id,
              name: script.name,
              script_type: script.script_type,
              interpreter: script.interpreter,
              description: script.description,
              enabled: script.enabled,
              priority: script.priority,
              content_size: script.content&.bytesize || 0
            }
          end

          def serialize_script_full(script)
            serialize_script(script).merge(
              content: script.content,
              config: script.respond_to?(:config) ? script.config : nil,
              checksum: calculate_checksum(script.content),
              created_at: script.created_at,
              updated_at: script.updated_at
            )
          end

          def calculate_checksum(content)
            return nil if content.blank?

            Digest::SHA256.hexdigest(content)
          end
        end
      end
    end
  end
end
