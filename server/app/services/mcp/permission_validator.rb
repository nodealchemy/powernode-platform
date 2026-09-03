# frozen_string_literal: true

# McpPermissionValidator - Validates user permissions for MCP tool execution
# Prevents over-privileged tool execution and tool combination attacks
#
# Two gates run here, and both can refuse: the tool's permission LEVEL and its
# REQUIRED PERMISSIONS. There is deliberately no third, scope-based gate.
#
# IMP-37471f8e1619 removed one. `validate_allowed_scopes` short-circuited on
# `tool.allowed_scopes.blank?`, and nothing writes that column. The four writers
# of the mcp_tools table are:
#
#   * Ai::Tools::McpPlatformToolRegistrar#upsert_mcp_tool!   (platform catalogue;
#     also the terminus of the mcp:sync_tools rake task)
#   * Api::V1::Internal::McpServersController#register_tools (worker-discovered
#     tools of externally-registered MCP servers)
#   * db/seeds/mcp_servers_seeds.rb                          (explicit setters)
#   * db/seeds/mcp_example_servers.rb                        (mass assignment —
#     `tool.assign_attributes(tool_attrs)` over a literal hash, so the attribute
#     list is in the DATA, not the call; every literal there carries only name,
#     description, input_schema and permission_level)
#
# The table has no create/update route (index/show only), no nested attributes,
# and no update_all/insert_all/upsert_all/raw UPDATE. Mcp::RegistryService — the
# only reader of the "allowedScopes" manifest key — keeps tools in memory: its
# #persist_tool_to_database is explicitly inert. The column therefore stays at
# its `{}` schema default and `{}.blank?` passed every check, while
# `authorization_result` advertised a "scope_permissions" refusal type. The
# taxonomy asserted coverage that could not exist.
#
# It was vacuous a second, independent way: `find_unauthorized_scopes` returned
# [] unconditionally and never consulted the user, making it a manifest
# well-formedness check wearing a permission-refusal label.
#
# Worth knowing before anyone rebuilds this: a scope PAYLOAD does exist upstream.
# examples/mcp-servers/shared/mcp-base.js:40 puts `allowedScopes` on every
# advertised tool, and stdio-filesystem/index.js populates it. It is discarded on
# ingest — worker/app/jobs/mcp/mcp_tool_discovery_job.rb#normalize_tool keeps only
# name/description/input_schema — so a declaring server's scopes never reach the
# column. That is the same declared-but-dropped shape as IMP-69c17aea6e81.
#
# Do NOT re-add a scope gate without BOTH of: a producer that actually writes the
# column, and a scope -> permission mapping covering all EIGHT scopes Doorkeeper
# accepts (config/initializers/doorkeeper.rb) rather than the four advertised by
# well_known_controller.rb — a token minted with `admin` falls straight through a
# map built from the advertised list.
# Guarded by spec/services/mcp/permission_validator_scope_gate_spec.rb.
module Mcp
  class PermissionValidator
  include ActiveModel::Model
  include ActiveModel::Attributes

  class PermissionDeniedError < StandardError; end

  # Scope catalogue: a well-formedness vocabulary, not an authorization gate.
  # Kept for Mcp::RegistryService#validate_allowed_scopes!, which checks an
  # in-memory MANIFEST key ("allowedScopes") — a different input from the column,
  # suppliable by an operator-written Ai::Agent#mcp_tool_manifest.
  # McpTool#validate_permission_fields also reads it, but that branch is gated by
  # `allowed_scopes.present?` — the same never-true condition the deleted gate
  # short-circuited on — so it is NOT independent justification. See the top of
  # the file.
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
      validate_required_permissions
  rescue PermissionDeniedError => e
    @logger.warn "[MCP_PERMISSION] Authorization failed: #{e.message}"
    false
  end

  # Get detailed authorization result with error messages
  def authorization_result
    errors = []

    # Check permission level
    unless permission_level_authorized?
      errors << {
        type: "permission_level",
        message: "Tool requires '#{tool.permission_level}' level access",
        required: tool.permission_level,
        actual: user_permission_level
      }
    end

    # Check required permissions
    missing_permissions = missing_required_permissions
    if missing_permissions.any?
      errors << {
        type: "required_permissions",
        message: "Missing required permissions: #{missing_permissions.join(', ')}",
        missing: missing_permissions,
        required: tool.required_permissions
      }
    end

    {
      authorized: errors.empty?,
      errors: errors,
      tool: {
        name: tool.name,
        permission_level: tool.permission_level,
        required_permissions: tool.required_permissions
      },
      user: {
        permission_level: user_permission_level,
        permissions: user_permissions
      }
    }
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

  def permission_level_authorized?
    case tool.permission_level
    when "public"
      true # Everyone can use public tools
    when "account"
      user_has_account_access?
    when "admin"
      # Admin tools require both admin permission AND account access
      user_is_admin? && user_has_account_access?
    else
      false
    end
  end

  def user_permission_level
    return "admin" if user_is_admin?
    return "account" if user_has_account_access?

    "public"
  end

  def user_is_admin?
    return false unless user

    # Use permission_names instead of permissions to get string-based comparison
    user.permission_names&.include?("system.admin") ||
      user.permission_names&.include?("admin.access")
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
  end
end
