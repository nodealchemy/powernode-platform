# frozen_string_literal: true

# Service for caching MCP tool discoveries to improve performance
class McpToolCacheService
  include Singleton

  CACHE_TTL = 5.minutes
  MAX_CACHE_SIZE = 1000

  def initialize
    @cache = {}
    @cache_timestamps = {}
    @mutex = Mutex.new
  end

  # Get cached tool manifest or fetch and cache it
  def get_tool_manifest(tool_id, account_id = nil)
    cache_key = build_cache_key(tool_id, account_id)

    @mutex.synchronize do
      if valid_cache_entry?(cache_key)
        Rails.logger.debug "[MCP_CACHE] Cache hit for tool: #{tool_id}"
        return @cache[cache_key]
      end

      Rails.logger.debug "[MCP_CACHE] Cache miss for tool: #{tool_id}, fetching..."
      manifest = fetch_tool_manifest(tool_id, account_id)

      if manifest
        store_in_cache(cache_key, manifest)
      end

      manifest
    end
  end

  # Get all tools for an account with caching
  def get_account_tools(account_id)
    cache_key = "account_tools_#{account_id}"

    @mutex.synchronize do
      if valid_cache_entry?(cache_key)
        Rails.logger.debug "[MCP_CACHE] Cache hit for account tools: #{account_id}"
        return @cache[cache_key]
      end

      Rails.logger.debug "[MCP_CACHE] Cache miss for account tools: #{account_id}"
      tools = fetch_account_tools(account_id)

      if tools
        store_in_cache(cache_key, tools)
      end

      tools
    end
  end

  # Invalidate cache for specific tool
  def invalidate_tool(tool_id, account_id = nil)
    cache_key = build_cache_key(tool_id, account_id)

    @mutex.synchronize do
      @cache.delete(cache_key)
      @cache_timestamps.delete(cache_key)
    end

    # Also invalidate account tools cache if account_id provided
    if account_id
      invalidate_account_tools(account_id)
    end

    Rails.logger.info "[MCP_CACHE] Invalidated cache for tool: #{tool_id}"
  end

  # Invalidate all tools for an account
  def invalidate_account_tools(account_id)
    cache_key = "account_tools_#{account_id}"

    @mutex.synchronize do
      @cache.delete(cache_key)
      @cache_timestamps.delete(cache_key)

      # Also remove individual tool entries for this account
      @cache.keys.select { |k| k.include?("_#{account_id}") }.each do |key|
        @cache.delete(key)
        @cache_timestamps.delete(key)
      end
    end

    Rails.logger.info "[MCP_CACHE] Invalidated cache for account: #{account_id}"
  end

  # Clear entire cache
  def clear_cache
    @mutex.synchronize do
      @cache.clear
      @cache_timestamps.clear
    end

    Rails.logger.info "[MCP_CACHE] Cache cleared"
  end

  # Get cache statistics
  def cache_stats
    @mutex.synchronize do
      {
        total_entries: @cache.size,
        memory_usage: estimate_memory_usage,
        oldest_entry: @cache_timestamps.values.min,
        newest_entry: @cache_timestamps.values.max,
        hit_rate: calculate_hit_rate
      }
    end
  end

  # Preload tools for better performance
  def preload_tools(account_id)
    Rails.logger.info "[MCP_CACHE] Preloading tools for account: #{account_id}"

    # Fetch all active agents for the account
    agents = AiAgent.where(account_id: account_id, status: "active")
      .includes(:ai_provider)
      .limit(100)

    agents.each do |agent|
      tool_id = "agent_#{agent.id}_v#{agent.version.gsub('.', '_')}"
      get_tool_manifest(tool_id, account_id)
    end

    Rails.logger.info "[MCP_CACHE] Preloaded #{agents.count} tools"
  end

  private

  def build_cache_key(tool_id, account_id)
    if account_id
      "#{tool_id}_#{account_id}"
    else
      tool_id.to_s
    end
  end

  def valid_cache_entry?(cache_key)
    return false unless @cache.key?(cache_key)
    return false unless @cache_timestamps.key?(cache_key)

    # Check if cache entry has expired
    timestamp = @cache_timestamps[cache_key]
    Time.current - timestamp < CACHE_TTL
  end

  def store_in_cache(cache_key, value)
    # Implement simple LRU eviction if cache is too large
    if @cache.size >= MAX_CACHE_SIZE
      evict_oldest_entries
    end

    @cache[cache_key] = value
    @cache_timestamps[cache_key] = Time.current

    # Track cache metrics
    increment_cache_metric(:writes)
  end

  def evict_oldest_entries
    # Remove 10% of oldest entries
    entries_to_remove = MAX_CACHE_SIZE / 10

    oldest_keys = @cache_timestamps.sort_by { |_, time| time }
      .first(entries_to_remove)
      .map(&:first)

    oldest_keys.each do |key|
      @cache.delete(key)
      @cache_timestamps.delete(key)
    end

    Rails.logger.debug "[MCP_CACHE] Evicted #{oldest_keys.size} oldest entries"
  end

  def fetch_tool_manifest(tool_id, account_id)
    # Extract agent ID from tool ID (format: agent_ID_vVERSION)
    if tool_id =~ /^agent_([a-f0-9-]+)_v/
      agent_id = $1
      agent = if account_id
                AiAgent.where(id: agent_id, account_id: account_id).first
      else
                AiAgent.find_by(id: agent_id)
      end

      return nil unless agent

      # Generate and return manifest
      agent.mcp_tool_manifest
    else
      # Try to find by other tool types (future expansion)
      nil
    end
  rescue StandardError => e
    Rails.logger.error "[MCP_CACHE] Error fetching tool manifest: #{e.message}"
    nil
  end

  def fetch_account_tools(account_id)
    account = Account.find_by(id: account_id)
    return [] unless account

    tools = []

    # Fetch AI agents
    agents = account.ai_agents.active.includes(:ai_provider)
    agents.each do |agent|
      manifest = agent.mcp_tool_manifest
      if manifest
        tools << {
          id: "agent_#{agent.id}_v#{agent.version.gsub('.', '_')}",
          manifest: manifest,
          type: "ai_agent",
          source: agent
        }
      end
    end

    # Future: Add other tool types (workflows, integrations, etc.)

    tools
  rescue StandardError => e
    Rails.logger.error "[MCP_CACHE] Error fetching account tools: #{e.message}"
    []
  end

  def estimate_memory_usage
    # Rough estimation of memory usage
    total_size = 0

    @cache.each_value do |value|
      total_size += value.to_s.bytesize
    end

    if total_size > 1_048_576 # 1 MB
      "#{(total_size / 1_048_576.0).round(2)} MB"
    elsif total_size > 1024 # 1 KB
      "#{(total_size / 1024.0).round(2)} KB"
    else
      "#{total_size} bytes"
    end
  end

  def calculate_hit_rate
    # This would need actual tracking of hits/misses
    # For now, return a placeholder
    @cache_hits ||= 0
    @cache_misses ||= 0
    total = @cache_hits + @cache_misses
    return 0.0 if total == 0

    (@cache_hits.to_f / total * 100).round(2)
  end

  def increment_cache_metric(metric)
    case metric
    when :hits
      @cache_hits = (@cache_hits || 0) + 1
    when :misses
      @cache_misses = (@cache_misses || 0) + 1
    when :writes
      @cache_writes = (@cache_writes || 0) + 1
    end
  end
end
