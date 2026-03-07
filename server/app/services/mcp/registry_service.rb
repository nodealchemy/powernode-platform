# frozen_string_literal: true

# MCP Registry Service - Centralized registry for MCP tool discovery and management
# Handles tool registration, capability matching, and version management
module Mcp
  class RegistryService
  include ActiveModel::Model
  include ActiveModel::Attributes

  class RegistryError < StandardError; end
  class ToolConflictError < RegistryError; end
  class DependencyError < RegistryError; end

  # Cache TTLs
  TOOL_LIST_CACHE_TTL = 1.hour
  CAPABILITY_SEARCH_CACHE_TTL = 1.hour

  attr_accessor :account

  def initialize(account: nil)
    @account = account
    @logger = Rails.logger
    @tools = {}
    @tool_dependencies = {}
    @tool_health = {}
    @version_index = {}
    @capability_index = {}
    @name_to_id_index = {}  # Add name-to-ID mapping for tool lookup by name

    # Initialize Redis connection for distributed registry if available
    @redis = Powernode::Redis.client

    load_existing_tools
  end

  # =============================================================================
  # TOOL REGISTRATION AND MANAGEMENT
  # =============================================================================

  # Register a new MCP tool in the registry
  def register_tool(tool_id, tool_manifest)
    @logger.info "[MCP_REGISTRY] Registering tool: #{tool_id}"

    # Validate tool manifest
    validate_tool_manifest!(tool_manifest)

    # Check for conflicts with existing tools
    check_tool_conflicts!(tool_id, tool_manifest)

    # Resolve dependencies
    resolve_dependencies!(tool_manifest)

    # Store tool in registry
    enhanced_manifest = enhance_tool_manifest(tool_manifest)
    store_tool(tool_id, enhanced_manifest)

    # Update indexes for discovery
    update_discovery_indexes(tool_id, enhanced_manifest)

    # Update name-to-ID mapping for tool lookup by name
    if enhanced_manifest["name"].present?
      @name_to_id_index[enhanced_manifest["name"]] = tool_id
      @logger.debug "[MCP_REGISTRY] Added name mapping: #{enhanced_manifest['name']} -> #{tool_id}"
    end

    # Mark tool as healthy
    mark_tool_healthy(tool_id)

    # Broadcast tool registration to connected clients
    broadcast_tool_registered(tool_id, enhanced_manifest)

    @logger.info "[MCP_REGISTRY] Tool registered successfully: #{tool_id}"
    tool_id
  end

  # Unregister a tool from the registry
  def unregister_tool(tool_id)
    @logger.info "[MCP_REGISTRY] Unregistering tool: #{tool_id}"

    # Check if tool is depended upon by others
    check_dependent_tools!(tool_id)

    # Remove from all indexes
    remove_from_indexes(tool_id)

    # Remove tool from storage
    remove_tool(tool_id)

    # Broadcast tool removal
    broadcast_tool_unregistered(tool_id)

    @logger.info "[MCP_REGISTRY] Tool unregistered: #{tool_id}"
  end

  # Update an existing tool registration
  def update_tool(tool_id, updated_manifest)
    @logger.info "[MCP_REGISTRY] Updating tool: #{tool_id}"

    existing_tool = get_tool(tool_id)
    raise RegistryError, "Tool not found: #{tool_id}" unless existing_tool

    # Validate compatibility with existing version
    validate_compatibility!(existing_tool, updated_manifest)

    # Update tool in registry
    enhanced_manifest = enhance_tool_manifest(updated_manifest)
    store_tool(tool_id, enhanced_manifest)

    # Update indexes
    update_discovery_indexes(tool_id, enhanced_manifest)

    # Broadcast tool update
    broadcast_tool_updated(tool_id, enhanced_manifest)

    @logger.info "[MCP_REGISTRY] Tool updated: #{tool_id}"
  end

  # =============================================================================
  # TOOL DISCOVERY AND QUERYING
  # =============================================================================

  # List all tools with optional filtering (cached for 1 hour when no filters)
  def list_tools(filters = {})
    # Use cache only for unfiltered queries
    if filters.empty? || filters.keys == [:sort_by]
      cache_key = "mcp:registry:tools:#{@account&.id || 'global'}:#{filters[:sort_by] || 'name'}"

      return Rails.cache.fetch(cache_key, expires_in: TOOL_LIST_CACHE_TTL) do
        tools = @tools.values
        sort_key = filters[:sort_by] || "name"
        tools.sort_by { |tool| tool[sort_key] || "" }
      end
    end

    # For filtered queries, don't cache (too many variations)
    tools = @tools.values

    # Apply filters
    tools = filter_by_capability(tools, filters[:capability]) if filters[:capability]
    tools = filter_by_version(tools, filters[:version]) if filters[:version]
    tools = filter_by_account(tools, filters[:account_id]) if filters[:account_id]
    tools = filter_by_health(tools, filters[:health_status]) if filters[:health_status]
    tools = filter_by_search(tools, filters[:search]) if filters[:search]

    # Sort tools
    sort_key = filters[:sort_by] || "name"
    tools.sort_by { |tool| tool[sort_key] || "" }
  end

  # Find tools by capability requirements (cached for 1 hour)
  def find_tools_by_capability(required_capabilities)
    # Sort capabilities for consistent cache key
    sorted_caps = required_capabilities.sort.join(",")
    cache_key = "mcp:registry:capabilities:#{@account&.id || 'global'}:#{Digest::MD5.hexdigest(sorted_caps)}"

    Rails.cache.fetch(cache_key, expires_in: CAPABILITY_SEARCH_CACHE_TTL) do
      matching_tools = []

      @capability_index.each do |capability, tool_ids|
        if required_capabilities.include?(capability)
          tool_ids.each do |tool_id|
            tool = @tools[tool_id]
            next unless tool

            # Check if tool supports ALL required capabilities
            tool_capabilities = extract_tool_capability_ids(tool)
            if (required_capabilities - tool_capabilities).empty?
              matching_tools << tool unless matching_tools.include?(tool)
            end
          end
        end
      end

      # Graph-based fallback: find tools with graph-adjacent capabilities
      if matching_tools.empty?
        begin
          graph_matches = find_tools_via_graph(required_capabilities)
          matching_tools.concat(graph_matches)
        rescue => e
          @logger.warn "[MCP_REGISTRY] Graph-based capability lookup failed: #{e.message}"
        end
      end

      matching_tools
    end
  end

  # Invalidate registry caches
  def invalidate_caches
    Rails.cache.delete_matched("mcp:registry:tools:#{@account&.id || 'global'}:*")
    Rails.cache.delete_matched("mcp:registry:capabilities:#{@account&.id || 'global'}:*")
  end

  # Get tool by ID or name
  def get_tool(identifier)
    # First try direct lookup by tool ID
    tool = @tools[identifier]
    actual_tool_id = identifier

    # If not found, try lookup by tool name using name-to-ID mapping
    if tool.nil? && @name_to_id_index[identifier]
      actual_tool_id = @name_to_id_index[identifier]
      tool = @tools[actual_tool_id]
      @logger.debug "[MCP_REGISTRY] Found tool by name lookup: #{identifier} -> #{actual_tool_id}"
    end

    # Check health status
    if tool && !tool_healthy?(actual_tool_id)
      @logger.warn "[MCP_REGISTRY] Tool unhealthy: #{actual_tool_id}"
      tool = tool.merge("health_status" => "unhealthy")
    end

    tool
  end

  # Check if tool exists in registry
  def tool_exists?(tool_id)
    @tools.key?(tool_id)
  end

  # Get tools by version pattern
  def get_tools_by_version(name_pattern, version_constraint)
    matching_tools = []

    @version_index.each do |tool_name, versions|
      next unless tool_name.match?(Regexp.new(name_pattern, Regexp::IGNORECASE))

      versions.each do |version, tool_id|
        if version_satisfies_constraint?(version, version_constraint)
          tool = @tools[tool_id]
          matching_tools << tool if tool
        end
      end
    end

    matching_tools
  end

  # =============================================================================
  # HEALTH MONITORING AND DEPENDENCIES
  # =============================================================================

  # Mark tool as healthy
  def mark_tool_healthy(tool_id)
    @tool_health[tool_id] = {
      status: "healthy",
      last_check: Time.current,
      last_error: nil
    }

    persist_health_status(tool_id, @tool_health[tool_id])
  end

  # Mark tool as unhealthy with error details
  def mark_tool_unhealthy(tool_id, error_message = nil)
    @tool_health[tool_id] = {
      status: "unhealthy",
      last_check: Time.current,
      last_error: error_message
    }

    persist_health_status(tool_id, @tool_health[tool_id])

    # Broadcast health change
    broadcast_tool_health_changed(tool_id, "unhealthy")

    @logger.warn "[MCP_REGISTRY] Tool marked unhealthy: #{tool_id} - #{error_message}"
  end

  # Check if tool is healthy
  def tool_healthy?(tool_id)
    health = @tool_health[tool_id]
    return false unless health

    health[:status] == "healthy"
  end

  # Get dependency chain for a tool
  def get_dependency_chain(tool_id)
    dependencies = []
    visited = Set.new

    build_dependency_chain(tool_id, dependencies, visited)
    dependencies
  end

  # Validate all tool dependencies are available
  def validate_dependencies!(tool_id)
    dependencies = @tool_dependencies[tool_id] || []

    missing_deps = dependencies.reject { |dep_id| tool_exists?(dep_id) && tool_healthy?(dep_id) }

    if missing_deps.any?
      raise DependencyError, "Missing or unhealthy dependencies for #{tool_id}: #{missing_deps.join(', ')}"
    end
  end

  # =============================================================================
  # REGISTRY SYNCHRONIZATION
  # =============================================================================

  # Sync registry with persistent storage
  def sync_registry
    @logger.info "[MCP_REGISTRY] Syncing registry with persistent storage"

    # Load tools from database
    database_tools = load_tools_from_database

    # Merge with in-memory registry
    database_tools.each do |tool_id, tool_manifest|
      @tools[tool_id] = tool_manifest
      update_discovery_indexes(tool_id, tool_manifest)
    end

    # Clean up orphaned entries
    cleanup_orphaned_entries

    @logger.info "[MCP_REGISTRY] Registry sync completed"
  end

  # Export registry state for backup/migration
  def export_registry
    {
      tools: @tools,
      dependencies: @tool_dependencies,
      health: @tool_health,
      indexes: {
        version: @version_index,
        capability: @capability_index
      },
      exported_at: Time.current.iso8601
    }
  end

  # Import registry state from backup
  def import_registry(registry_data)
    @logger.info "[MCP_REGISTRY] Importing registry data"

    @tools = registry_data["tools"] || {}
    @tool_dependencies = registry_data["dependencies"] || {}
    @tool_health = registry_data["health"] || {}

    if registry_data["indexes"]
      @version_index = registry_data["indexes"]["version"] || {}
      @capability_index = registry_data["indexes"]["capability"] || {}
    end

    @logger.info "[MCP_REGISTRY] Registry import completed"
  end

  # =============================================================================
  # PRIVATE HELPER METHODS
  # =============================================================================

  private

  def load_existing_tools
    # Load tools from database for this account
    return unless @account

    ai_agents = @account.ai_agents.active
    ai_agents.each do |agent|
      # Use the agent's existing MCP tool manifest and consistent tool ID format
      tool_manifest = agent.mcp_tool_manifest
      tool_id = "agent_#{agent.id}_v#{agent.version.gsub('.', '_')}"

      @tools[tool_id] = tool_manifest
      update_discovery_indexes(tool_id, tool_manifest)

      # Add name-to-ID mapping for tool lookup by name
      if tool_manifest["name"].present?
        @name_to_id_index[tool_manifest["name"]] = tool_id
      end

      mark_tool_healthy(tool_id)
    end

    @logger.info "[MCP_REGISTRY] Loaded #{@tools.size} existing tools"
  end

  def validate_tool_manifest!(manifest)
    required_fields = %w[name description type version inputSchema outputSchema]
    missing_fields = required_fields - manifest.keys

    if missing_fields.any?
      raise RegistryError, "Missing required fields: #{missing_fields.join(', ')}"
    end

    # Validate version format (semantic versioning)
    unless manifest["version"].match?(/\A\d+\.\d+\.\d+\z/)
      raise RegistryError, "Invalid version format: #{manifest['version']}"
    end

    # Validate permission fields if present
    validate_permission_level!(manifest) if manifest["permissionLevel"]
    validate_required_permissions!(manifest) if manifest["requiredPermissions"]
    validate_allowed_scopes!(manifest) if manifest["allowedScopes"]
  end

  def validate_permission_level!(manifest)
    permission_level = manifest["permissionLevel"]
    valid_levels = %w[public account admin]

    unless valid_levels.include?(permission_level)
      raise RegistryError, "Invalid permission level: #{permission_level}. Must be one of: #{valid_levels.join(', ')}"
    end
  end

  def validate_required_permissions!(manifest)
    required_permissions = manifest["requiredPermissions"]

    unless required_permissions.is_a?(Array)
      raise RegistryError, "requiredPermissions must be an array"
    end

    # Validate each permission is a string
    required_permissions.each do |permission|
      unless permission.is_a?(String)
        raise RegistryError, "Each permission in requiredPermissions must be a string"
      end
    end
  end

  def validate_allowed_scopes!(manifest)
    allowed_scopes = manifest["allowedScopes"]

    unless allowed_scopes.is_a?(Hash)
      raise RegistryError, "allowedScopes must be a hash"
    end

    # Validate scope structure against McpPermissionValidator constants
    valid_categories = Mcp::PermissionValidator::TOOL_PERMISSION_SCOPES.keys.map(&:to_s)

    allowed_scopes.each do |category, permissions|
      unless valid_categories.include?(category)
        raise RegistryError, "Invalid scope category: #{category}. Must be one of: #{valid_categories.join(', ')}"
      end

      unless permissions.is_a?(Array)
        raise RegistryError, "Permissions for scope #{category} must be an array"
      end

      # Validate each permission in the category
      valid_permissions = Mcp::PermissionValidator::TOOL_PERMISSION_SCOPES[category.to_sym].map(&:to_s)
      permissions.each do |permission|
        unless valid_permissions.include?(permission)
          raise RegistryError, "Invalid permission '#{permission}' for scope '#{category}'. Valid permissions: #{valid_permissions.join(', ')}"
        end
      end
    end
  end

  def check_tool_conflicts!(tool_id, manifest)
    existing_tool = @tools[tool_id]
    return unless existing_tool

    # Check if this is a version conflict
    if existing_tool["name"] == manifest["name"] &&
       existing_tool["version"] == manifest["version"]
      raise ToolConflictError, "Tool with same name and version already exists: #{tool_id}"
    end
  end

  def resolve_dependencies!(manifest)
    dependencies = manifest["dependencies"] || []

    dependencies.each do |dep_name|
      unless find_tool_by_name(dep_name)
        @logger.warn "[MCP_REGISTRY] Dependency not found: #{dep_name}"
      end
    end
  end

  def enhance_tool_manifest(manifest)
    manifest.merge(
      "registered_at" => Time.current.iso8601,
      "account_id" => @account&.id,
      "registry_version" => "1.0.0"
    )
  end

  def store_tool(tool_id, manifest)
    @tools[tool_id] = manifest

    # Persist to Redis if available
    if @redis
      @redis.hset("mcp:registry:#{@account&.id || 'global'}", tool_id, manifest.to_json)
    end

    # Persist to database
    persist_tool_to_database(tool_id, manifest)
  end

  def remove_tool(tool_id)
    @tools.delete(tool_id)

    # Remove from Redis
    if @redis
      @redis.hdel("mcp:registry:#{@account&.id || 'global'}", tool_id)
    end

    # Remove from database
    remove_tool_from_database(tool_id)
  end

  def update_discovery_indexes(tool_id, manifest)
    # Update version index
    tool_name = manifest["name"]
    tool_version = manifest["version"]

    @version_index[tool_name] ||= {}
    @version_index[tool_name][tool_version] = tool_id

    # Update capability index
    capabilities = manifest["capabilities"] || []
    capabilities.each do |capability|
      @capability_index[capability] ||= []
      @capability_index[capability] << tool_id unless @capability_index[capability].include?(tool_id)
    end
  end

  def remove_from_indexes(tool_id)
    tool = @tools[tool_id]
    return unless tool

    # Remove from version index
    tool_name = tool["name"]
    tool_version = tool["version"]
    @version_index[tool_name]&.delete(tool_version)

    # Remove from name-to-ID mapping
    if tool_name.present?
      @name_to_id_index.delete(tool_name)
      @logger.debug "[MCP_REGISTRY] Removed name mapping: #{tool_name}"
    end

    # Remove from capability index
    capabilities = tool["capabilities"] || []
    capabilities.each do |capability|
      @capability_index[capability]&.delete(tool_id)
    end
  end

  def filter_by_capability(tools, capability)
    tools.select { |tool| (tool["capabilities"] || []).include?(capability) }
  end

  def filter_by_version(tools, version_constraint)
    tools.select { |tool| version_satisfies_constraint?(tool["version"], version_constraint) }
  end

  def filter_by_account(tools, account_id)
    tools.select { |tool| tool["account_id"] == account_id }
  end

  def filter_by_health(tools, health_status)
    tools.select do |tool|
      tool_id = generate_tool_id_from_manifest(tool)
      health = @tool_health[tool_id]
      health&.dig(:status) == health_status
    end
  end

  def filter_by_search(tools, search_term)
    search_regex = Regexp.new(search_term, Regexp::IGNORECASE)
    tools.select do |tool|
      tool["name"].match?(search_regex) ||
      tool["description"].match?(search_regex)
    end
  end

  def version_satisfies_constraint?(version, constraint)
    # Simple version constraint matching (can be enhanced with semver gem)
    case constraint
    when /\A>=(.+)\z/
      Gem::Version.new(version) >= Gem::Version.new($1)
    when /\A>(.+)\z/
      Gem::Version.new(version) > Gem::Version.new($1)
    when /\A<=(.+)\z/
      Gem::Version.new(version) <= Gem::Version.new($1)
    when /\A<(.+)\z/
      Gem::Version.new(version) < Gem::Version.new($1)
    when /\A~>(.+)\z/
      # Pessimistic version constraint
      base_version = Gem::Version.new($1)
      Gem::Version.new(version) >= base_version &&
      Gem::Version.new(version) < base_version.bump
    else
      version == constraint
    end
  end

  def build_dependency_chain(tool_id, dependencies, visited)
    return if visited.include?(tool_id)
    visited.add(tool_id)

    tool_deps = @tool_dependencies[tool_id] || []
    tool_deps.each do |dep_id|
      dependencies << dep_id
      build_dependency_chain(dep_id, dependencies, visited)
    end
  end

  def check_dependent_tools!(tool_id)
    dependent_tools = []

    @tool_dependencies.each do |tid, deps|
      dependent_tools << tid if deps.include?(tool_id)
    end

    if dependent_tools.any?
      raise DependencyError, "Cannot unregister tool #{tool_id}: required by #{dependent_tools.join(', ')}"
    end
  end

  def validate_compatibility!(existing_tool, updated_manifest)
    # Check major version compatibility
    existing_version = Gem::Version.new(existing_tool["version"])
    updated_version = Gem::Version.new(updated_manifest["version"])

    if updated_version.segments[0] != existing_version.segments[0]
      @logger.warn "[MCP_REGISTRY] Major version change detected for tool update"
    end
  end

  def generate_agent_tool_manifest(agent)
    {
      "name" => agent.name,
      "description" => agent.description || "AI Agent: #{agent.name}",
      "type" => "ai_agent",
      "version" => agent.version.to_s,
      "capabilities" => agent.skill_slugs,
      "inputSchema" => agent.mcp_input_schema || default_agent_input_schema,
      "outputSchema" => agent.mcp_output_schema || default_agent_output_schema,
      "agent_id" => agent.id,
      "provider_id" => agent.ai_provider_id
    }
  end

  def find_tool_by_name(name)
    @tools.values.find { |tool| tool["name"] == name }
  end

  # Graph-based tool discovery fallback
  def find_tools_via_graph(required_capabilities)
    return [] unless @account&.ai_knowledge_graph_nodes&.active&.skill_nodes&.exists?

    graph_service = Ai::KnowledgeGraph::GraphService.new(@account)
    graph_matched_tool_ids = Set.new

    required_capabilities.each do |cap|
      cap_skill = Ai::Skill.for_account(@account.id).active.find_by(slug: cap)
      cap_node = cap_skill&.knowledge_graph_node
      next unless cap_node&.status == "active"

      neighbors = graph_service.find_neighbors(node: cap_node, depth: 1, relation_types: %w[requires related_to])
      neighbor_names = neighbors.map { |n| n[:name] }.compact

      neighbor_names.each do |name|
        tool_ids = @capability_index[name]
        graph_matched_tool_ids.merge(tool_ids) if tool_ids
      end
    end

    graph_matched_tool_ids.filter_map { |tid| @tools[tid] }
  end

  def extract_tool_capability_ids(tool)
    caps = tool["capabilities"] || []
    caps.map { |c| c.is_a?(Hash) ? (c["id"] || c["name"]) : c.to_s }.compact
  end

  def generate_tool_id_from_manifest(manifest)
    name = manifest["name"].downcase.gsub(/[^a-z0-9]/, "_")
    version = manifest["version"].gsub(".", "_")
    "#{name}_v#{version}"
  end

  def default_agent_input_schema
    {
      "type" => "object",
      "properties" => {
        "input" => {
          "type" => "string",
          "description" => "Input text for the AI agent"
        }
      },
      "required" => [ "input" ]
    }
  end

  def default_agent_output_schema
    {
      "type" => "object",
      "properties" => {
        "output" => {
          "type" => "string",
          "description" => "Generated response from the AI agent"
        },
        "metadata" => {
          "type" => "object",
          "description" => "Additional metadata about the response"
        }
      },
      "required" => [ "output" ]
    }
  end

  def persist_health_status(tool_id, health_status)
    # Persist to Redis if available
    if @redis
      @redis.hset("mcp:health:#{@account&.id || 'global'}", tool_id, health_status.to_json)
    end
  end

  def persist_tool_to_database(tool_id, manifest)
    # Implementation would depend on database schema
    # For now, we'll store in Redis/memory
  end

  def remove_tool_from_database(tool_id)
    # Implementation would depend on database schema
  end

  def load_tools_from_database
    # Implementation would load from persistent storage
    {}
  end

  def cleanup_orphaned_entries
    # Remove entries that no longer have corresponding database records
  end

  def broadcast_tool_registered(tool_id, manifest)
    Mcp::BroadcastService.broadcast_tool_event("registered", tool_id, manifest, @account)
  end

  def broadcast_tool_unregistered(tool_id)
    Mcp::BroadcastService.broadcast_tool_event("unregistered", tool_id, nil, @account)
  end

  def broadcast_tool_updated(tool_id, manifest)
    Mcp::BroadcastService.broadcast_tool_event("updated", tool_id, manifest, @account)
  end

  def broadcast_tool_health_changed(tool_id, health_status)
    Mcp::BroadcastService.broadcast_tool_event("health_changed", tool_id, { health_status: health_status }, @account)
  end
  end
end
