# frozen_string_literal: true

# McpPermissionValidator - Validates user permissions for MCP tool execution
# Prevents over-privileged tool execution and tool combination attacks
class McpPermissionValidator
  include ActiveModel::Model
  include ActiveModel::Attributes

  class PermissionDeniedError < StandardError; end
  class InvalidScopeError < StandardError; end

  # Tool permission scopes following the audit roadmap
  TOOL_PERMISSION_SCOPES = {
    file_access: %i[read_files write_files delete_files list_directories],
    network: %i[http_get http_post external_api email_send webhook_call],
    data: %i[read_user_data read_account_data read_credentials read_pii],
    system: %i[execute_commands environment_access process_spawn],
    ai: %i[call_other_agents modify_workflow access_conversation_history]
  }.freeze

  PERMISSION_LEVELS = %w[public account admin].freeze

  attr_accessor :tool, :user, :account

  def initialize(tool:, user:, account:)
    @tool = tool
    @user = user
    @account = account
    @logger = Rails.logger
  end

  # Check if user is authorized to execute this tool
  def authorized?
    validate_permission_level &&
      validate_required_permissions &&
      validate_allowed_scopes
  rescue PermissionDeniedError, InvalidScopeError => e
    @logger.warn "[MCP_PERMISSION] Authorization failed: #{e.message}"
    false
  end

  # Get detailed authorization result with error messages
  def authorization_result
    errors = []

    # Check permission level
    unless permission_level_authorized?
      errors << {
        type: 'permission_level',
        message: "Tool requires '#{tool.permission_level}' level access",
        required: tool.permission_level,
        actual: user_permission_level
      }
    end

    # Check required permissions
    missing_permissions = missing_required_permissions
    if missing_permissions.any?
      errors << {
        type: 'required_permissions',
        message: "Missing required permissions: #{missing_permissions.join(', ')}",
        missing: missing_permissions,
        required: tool.required_permissions
      }
    end

    # Check allowed scopes
    unless all_scopes_permitted?
      unauthorized_scopes = find_unauthorized_scopes
      errors << {
        type: 'scope_permissions',
        message: "Unauthorized scopes: #{unauthorized_scopes.join(', ')}",
        unauthorized: unauthorized_scopes,
        allowed: tool.allowed_scopes
      }
    end

    {
      authorized: errors.empty?,
      errors: errors,
      tool: {
        name: tool.name,
        permission_level: tool.permission_level,
        required_permissions: tool.required_permissions,
        allowed_scopes: tool.allowed_scopes
      },
      user: {
        permission_level: user_permission_level,
        permissions: user_permissions
      }
    }
  end

  # Validate that a specific scope operation is permitted
  def scope_permitted?(scope_category, scope_permission)
    return true if tool.allowed_scopes.blank?

    scopes_for_category = tool.allowed_scopes[scope_category.to_s] || []
    scopes_for_category.include?(scope_permission.to_s)
  end

  # Check if user has a specific permission
  def has_permission?(permission)
    user_permissions.include?(permission.to_s)
  end

  # Get all permissions the current user has
  def user_permissions
    @user_permissions ||= begin
      return [] unless user

      # Get permissions from user's roles (returns array of permission name strings)
      user.permission_names || []
    end
  end

  private

  def validate_permission_level
    unless permission_level_authorized?
      raise PermissionDeniedError,
            "Tool '#{tool.name}' requires '#{tool.permission_level}' access level"
    end
    true
  end

  def validate_required_permissions
    missing = missing_required_permissions

    if missing.any?
      raise PermissionDeniedError,
            "Missing required permissions for tool '#{tool.name}': #{missing.join(', ')}"
    end
    true
  end

  def validate_allowed_scopes
    return true if tool.allowed_scopes.blank? # No scope restrictions

    unless all_scopes_valid?
      invalid = find_invalid_scopes
      raise InvalidScopeError,
            "Tool '#{tool.name}' has invalid scopes: #{invalid.join(', ')}"
    end

    # All scopes are valid, no need for runtime user scope validation
    # Scopes are enforced at execution time via scope_permitted? method
    true
  end

  def permission_level_authorized?
    case tool.permission_level
    when 'public'
      true # Everyone can use public tools
    when 'account'
      user_has_account_access?
    when 'admin'
      # Admin tools require both admin permission AND account access
      user_is_admin? && user_has_account_access?
    else
      false
    end
  end

  def user_permission_level
    return 'admin' if user_is_admin?
    return 'account' if user_has_account_access?

    'public'
  end

  def user_is_admin?
    return false unless user

    user.permissions&.include?('system.admin') ||
      user.permissions&.include?('admin.access')
  end

  def user_has_account_access?
    return false unless user || account

    # User is part of this account
    user&.account_id == account&.id
  end

  def missing_required_permissions
    return [] if tool.required_permissions.blank?

    required = Array(tool.required_permissions)
    current = user_permissions

    required - current
  end

  def all_scopes_permitted?
    # If no scopes defined, all are permitted
    return true if tool.allowed_scopes.blank?

    # All defined scopes must be valid
    all_scopes_valid?
  end

  def all_scopes_valid?
    return true if tool.allowed_scopes.blank?

    tool.allowed_scopes.all? do |category, permissions|
      # Check category is valid
      next false unless TOOL_PERMISSION_SCOPES.key?(category.to_sym)

      # Check all permissions in category are valid
      allowed_permissions = TOOL_PERMISSION_SCOPES[category.to_sym].map(&:to_s)
      Array(permissions).all? { |perm| allowed_permissions.include?(perm.to_s) }
    end
  end

  def find_invalid_scopes
    return [] if tool.allowed_scopes.blank?

    invalid = []

    tool.allowed_scopes.each do |category, permissions|
      unless TOOL_PERMISSION_SCOPES.key?(category.to_sym)
        invalid << "#{category} (invalid category)"
        next
      end

      allowed_permissions = TOOL_PERMISSION_SCOPES[category.to_sym].map(&:to_s)
      Array(permissions).each do |perm|
        unless allowed_permissions.include?(perm.to_s)
          invalid << "#{category}.#{perm}"
        end
      end
    end

    invalid
  end

  def find_unauthorized_scopes
    # For audit reporting - not currently enforcing user-level scope restrictions
    # This would be used if we implement per-user scope limitations
    []
  end
end
