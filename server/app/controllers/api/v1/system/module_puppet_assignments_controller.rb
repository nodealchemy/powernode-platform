# frozen_string_literal: true

module Api
  module V1
    module System
      class ModulePuppetAssignmentsController < BaseController
        before_action :set_node_module
        before_action :set_assignment, only: [:show, :update, :destroy]

        # GET /api/v1/system/node_modules/:node_module_id/puppet_assignments
        def index
          authorize_permission!('system.puppet.read')

          assignments = @node_module.module_puppet_assignments
                                     .includes(:puppet_module)
                                     .by_priority

          assignments = assignments.enabled if params[:enabled] == 'true'
          assignments = paginate(assignments)

          render_success(
            puppet_assignments: assignments.map { |a| ::System::ModulePuppetAssignmentSerializer.new(a).as_json },
            meta: pagination_meta
          )
        end

        # GET /api/v1/system/node_modules/:node_module_id/puppet_assignments/:id
        def show
          authorize_permission!('system.puppet.read')
          render_success(puppet_assignment: ::System::ModulePuppetAssignmentSerializer.new(@assignment).as_json)
        end

        # POST /api/v1/system/node_modules/:node_module_id/puppet_assignments
        def create
          authorize_permission!('system.puppet.create')

          assignment = @node_module.module_puppet_assignments.build(assignment_params)

          if assignment.save
            render_success(puppet_assignment: ::System::ModulePuppetAssignmentSerializer.new(assignment).as_json, status: :created)
          else
            render_validation_error(assignment)
          end
        end

        # PATCH/PUT /api/v1/system/node_modules/:node_module_id/puppet_assignments/:id
        def update
          authorize_permission!('system.puppet.update')

          if @assignment.update(assignment_params)
            render_success(puppet_assignment: ::System::ModulePuppetAssignmentSerializer.new(@assignment).as_json)
          else
            render_validation_error(@assignment)
          end
        end

        # DELETE /api/v1/system/node_modules/:node_module_id/puppet_assignments/:id
        def destroy
          authorize_permission!('system.puppet.delete')
          @assignment.destroy
          render_success(message: 'Puppet assignment removed successfully')
        end

        private

        def set_node_module
          @node_module = current_account.system_node_modules.find(params[:node_module_id])
        end

        def set_assignment
          @assignment = @node_module.module_puppet_assignments.find(params[:id])
        end

        def assignment_params
          params.require(:puppet_assignment).permit(
            :puppet_module_id, :enabled, :priority,
            config: {},
            parameters: {}
          )
        end
      end
    end
  end
end
