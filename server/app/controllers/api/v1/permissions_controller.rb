# frozen_string_literal: true

class Api::V1::PermissionsController < ApplicationController
  before_action :require_admin_permission

  # GET /api/v1/permissions
  # The code-defined catalog is the source of truth for the permission list.
  def index
    render_success(
      data: Permissions.all_permissions.keys.sort.map { |name| permission_data(name) }
    )
  end

  # GET /api/v1/permissions/:id  (:id is the permission name)
  def show
    name = params[:id].to_s
    unless Permissions.permission_exists?(name)
      return render_error("Permission not found", status: :not_found)
    end

    render_success(data: permission_data(name))
  end

  private

  def require_admin_permission
    # Allow users with admin.role.read or admin.access permissions to view permissions
    unless current_user&.has_permission?("admin.role.read") ||
           current_user&.has_permission?("admin.access") ||
           current_user&.has_permission?("system.admin")
      render_error("Unauthorized access to permissions", status: :forbidden)
    end
  end

  # Builds the API shape from a catalog permission name. resource/action are
  # parsed from the dotted name (e.g. "ai.agents.create" -> resource "ai.agents",
  # action "create"); the leading segment is the tier for admin./system. perms.
  def permission_data(name)
    parts = name.split(".")
    {
      id: name,
      name: name,
      resource: parts[0..-2].join("."),
      action: parts.last,
      description: Permissions.permission_description(name),
      roles_count: RolePermission.where(permission_name: name).count
    }
  end
end
