# frozen_string_literal: true

module Api
  module V1
    module Auth
      class PermissionsController < ApplicationController

        # GET /api/v1/auth/permissions
        # Returns current user/worker permissions
        def index
          if current_user
            render_success(user_permissions)
          elsif current_worker
            render_success(worker_permissions)
          elsif current_service
            render_success(service_permissions)
          else
            render_error('Authentication required', status: :unauthorized)
          end
        end

        # GET /api/v1/auth/permissions/check
        # Check specific permissions
        def check
          permissions_to_check = params[:permissions]

          if permissions_to_check.blank?
            return render_error('Permissions parameter required')
          end

          permissions_to_check = [permissions_to_check] unless permissions_to_check.is_a?(Array)

          current_permissions = if current_user
                                  current_user.permission_names
                                elsif current_worker
                                  current_worker.permission_names
                                elsif current_service
                                  # Service tokens have all permissions by default
                                  permissions_to_check
                                else
                                  []
                                end

          results = permissions_to_check.map do |permission|
            {
              permission: permission,
              granted: current_permissions.include?(permission)
            }
          end

          render_success({
            permissions: results,
            has_all: results.all? { |r| r[:granted] },
            has_any: results.any? { |r| r[:granted] }
          })
        end

        private

        def user_permissions
          {
            type: 'user',
            user_id: current_user.id,
            account_id: current_user.account_id,
            email: current_user.email,
            roles: current_user.role_names,
            permissions: current_user.permission_names,
            permission_version: calculate_permission_version(current_user),
            account_status: current_user.account.status,
            user_status: current_user.status
          }
        end

        def worker_permissions
          {
            type: 'worker',
            worker_id: current_worker.id,
            account_id: current_worker.account_id,
            name: current_worker.name,
            worker_type: current_worker.system? ? 'system' : 'account',
            roles: current_worker.role_names,
            permissions: current_worker.permission_names,
            permission_version: calculate_worker_permission_version(current_worker),
            worker_status: current_worker.status
          }
        end

        def service_permissions
          {
            type: 'service',
            service: current_service,
            permissions: ['*'], # Service tokens have all permissions
            permission_version: 'service'
          }
        end

        def calculate_permission_version(user)
          permissions_string = user.permission_names.sort.join(',')
          Digest::SHA256.hexdigest(permissions_string)[0..7]
        end

        def calculate_worker_permission_version(worker)
          permissions_string = worker.permission_names.sort.join(',')
          Digest::SHA256.hexdigest(permissions_string)[0..7]
        end
      end
    end
  end
end