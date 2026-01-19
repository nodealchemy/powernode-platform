# frozen_string_literal: true

# McpServer represents a Model Context Protocol server connection
class McpServer < ApplicationRecord
  # ==========================================
  # Concerns
  # ==========================================
  include Auditable

  # ==========================================
  # Authentication & Authorization
  # ==========================================
  belongs_to :account

  # ==========================================
  # Associations
  # ==========================================
  has_many :mcp_tools, dependent: :destroy

  # ==========================================
  # Validations
  # ==========================================
  validates :name, presence: true
  validates :name, uniqueness: { scope: :account_id }
  validates :status, presence: true, inclusion: {
    in: %w[connected disconnected connecting error],
    message: "must be a valid status"
  }
  validates :connection_type, presence: true, inclusion: {
    in: %w[stdio websocket http],
    message: "must be stdio, websocket, or http"
  }
  validates :auth_type, presence: true, inclusion: {
    in: %w[none api_key oauth2],
    message: "must be none, api_key, or oauth2"
  }

  validate :validate_connection_configuration
  validate :validate_args_format
  validate :validate_env_format
  validate :validate_capabilities_format
  validate :validate_oauth_configuration, if: -> { auth_type == "oauth2" }

  # ==========================================
  # Scopes
  # ==========================================
  scope :connected, -> { where(status: "connected") }
  scope :disconnected, -> { where(status: "disconnected") }
  scope :active, -> { where(status: "connected") }
  scope :inactive, -> { where(status: %w[disconnected error]) }
  scope :for_account, ->(account_id) { where(account_id: account_id) }
  scope :by_connection_type, ->(type) { where(connection_type: type) }
  scope :recently_checked, -> { where("last_health_check > ?", 5.minutes.ago) }
  scope :needs_health_check, -> { where("last_health_check IS NULL OR last_health_check < ?", 5.minutes.ago) }

  # ==========================================
  # Callbacks
  # ==========================================
  before_validation :set_default_values, on: :create
  after_create :initialize_connection
  after_update :broadcast_status_change, if: :saved_change_to_status?

  # ==========================================
  # Virtual Attributes (for API compatibility)
  # ==========================================

  # URL for http/websocket connections - stored in command or env
  def url
    return command if connection_type.in?(%w[http websocket]) && command&.start_with?("http")

    env&.dig("MCP_URL") || env&.dig("URL")
  end

  def url=(value)
    if connection_type.in?(%w[http websocket])
      self.command = value
      self.env ||= {}
      self.env["MCP_URL"] = value
    end
  end

  # Alias last_health_check as last_connected_at for API compatibility
  def last_connected_at
    last_health_check
  end

  # Last error is stored in capabilities or a default message
  def last_error
    capabilities&.dig("last_error")
  end

  def last_error=(value)
    self.capabilities ||= {}
    self.capabilities["last_error"] = value
  end

  # Config stored in capabilities for API compatibility
  def config
    capabilities&.dig("config") || {}
  end

  def config=(value)
    self.capabilities ||= {}
    self.capabilities["config"] = value
  end

  # ==========================================
  # Public Methods
  # ==========================================

  # Status check methods
  def connected?
    status == "connected"
  end

  def disconnected?
    status == "disconnected"
  end

  def connecting?
    status == "connecting"
  end

  def error?
    status == "error"
  end

  # Connection management - delegates to worker service for async execution
  def connect!
    update!(status: "connecting")

    begin
      # Queue connection job in worker service
      WorkerJobService.enqueue_mcp_server_connection(id, action: "connect")
      Rails.logger.info "Queued MCP server connection job for #{name} (#{id})"
    rescue WorkerJobService::WorkerServiceError => e
      Rails.logger.error "Failed to queue MCP server connection job for #{name}: #{e.message}"
      update!(
        status: "error",
        capabilities: (capabilities || {}).merge("last_error" => "Failed to queue connection: #{e.message}")
      )
    end
  end

  def disconnect!
    begin
      # Queue disconnection job in worker service
      WorkerJobService.enqueue_mcp_server_connection(id, action: "disconnect")
      update!(status: "disconnected", last_health_check: Time.current)
      Rails.logger.info "Queued MCP server disconnection job for #{name} (#{id})"
    rescue WorkerJobService::WorkerServiceError => e
      Rails.logger.error "Failed to queue MCP server disconnection job for #{name}: #{e.message}"
      # Still mark as disconnected locally
      update!(status: "disconnected", last_health_check: Time.current)
    end
  end

  # Health check - synchronous version that updates last_health_check
  def health_check
    return false unless connected?

    update!(last_health_check: Time.current)
    true
  rescue StandardError => e
    Rails.logger.error "Health check failed for MCP server #{name}: #{e.message}"
    false
  end

  # Health check - delegates to worker service for async execution
  def health_check!
    return false unless connected?

    begin
      # Queue health check job in worker service
      WorkerJobService.enqueue_mcp_health_check(id)
      Rails.logger.info "Queued MCP health check job for #{name} (#{id})"
      true
    rescue WorkerJobService::WorkerServiceError => e
      Rails.logger.error "Failed to queue health check for MCP server #{name}: #{e.message}"
      false
    end
  end

  # Tool discovery - delegates to worker service for async execution
  def discover_tools
    return [] unless connected?

    begin
      # Queue tool discovery job in worker service
      WorkerJobService.enqueue_mcp_tool_discovery(id)
      Rails.logger.info "Queued MCP tool discovery job for #{name} (#{id})"
      mcp_tools.reload
    rescue WorkerJobService::WorkerServiceError => e
      Rails.logger.error "Failed to queue MCP tool discovery job for #{name}: #{e.message}"
      []
    end
  end

  # Get server info
  def server_info
    {
      id: id,
      name: name,
      status: status,
      connection_type: connection_type,
      tool_count: mcp_tools.count,
      capabilities: capabilities,
      last_health_check: last_health_check,
      uptime: calculate_uptime
    }
  end

  # Get environment variables for connection
  def connection_env
    env.merge(
      "MCP_SERVER_NAME" => name,
      "MCP_SERVER_ID" => id
    )
  end

  # ==========================================
  # OAuth Methods
  # ==========================================

  # Check if OAuth is configured
  def oauth_configured?
    auth_type == "oauth2" && oauth_client_id.present?
  end

  # Check if OAuth is connected (has valid tokens)
  def oauth_connected?
    oauth_configured? && oauth_access_token.present? && !oauth_token_expired?
  end

  # Check if OAuth token has expired
  def oauth_token_expired?
    return true unless oauth_token_expires_at

    oauth_token_expires_at <= Time.current
  end

  # Check if OAuth token is expiring soon (within minutes)
  def oauth_token_expiring_soon?(minutes = 5)
    return true unless oauth_token_expires_at

    oauth_token_expires_at <= minutes.minutes.from_now
  end

  # Decrypt and return access token
  def oauth_access_token
    return nil unless oauth_access_token_encrypted.present?

    decrypt_oauth_token(oauth_access_token_encrypted)
  end

  # Encrypt and store access token
  def oauth_access_token=(token)
    self.oauth_access_token_encrypted = encrypt_oauth_token(token)
  end

  # Decrypt and return refresh token
  def oauth_refresh_token
    return nil unless oauth_refresh_token_encrypted.present?

    decrypt_oauth_token(oauth_refresh_token_encrypted)
  end

  # Encrypt and store refresh token
  def oauth_refresh_token=(token)
    self.oauth_refresh_token_encrypted = encrypt_oauth_token(token)
  end

  # Decrypt and return client secret
  def oauth_client_secret
    return nil unless oauth_client_secret_encrypted.present?

    decrypt_oauth_token(oauth_client_secret_encrypted)
  end

  # Encrypt and store client secret
  def oauth_client_secret=(secret)
    self.oauth_client_secret_encrypted = encrypt_oauth_token(secret)
  end

  # Clear all OAuth tokens (for disconnect)
  def clear_oauth_tokens!
    update!(
      oauth_access_token_encrypted: nil,
      oauth_refresh_token_encrypted: nil,
      oauth_token_expires_at: nil,
      oauth_state: nil,
      oauth_pkce_code_verifier: nil,
      oauth_error: nil
    )
  end

  # Get OAuth status summary
  def oauth_status
    {
      auth_type: auth_type,
      oauth_configured: oauth_configured?,
      oauth_connected: oauth_connected?,
      oauth_token_expires_at: oauth_token_expires_at,
      oauth_token_expired: oauth_token_expired?,
      oauth_last_refreshed_at: oauth_last_refreshed_at,
      oauth_error: oauth_error,
      oauth_provider: oauth_provider,
      oauth_scopes: oauth_scopes
    }
  end

  # ==========================================
  # Private Methods
  # ==========================================
  private

  # Encrypt OAuth token using application credential encryption service
  # Uses 'mcp' namespace for key isolation from other components
  def encrypt_oauth_token(value)
    return nil if value.blank?

    Security::CredentialEncryptionService.encrypt_value(value, namespace: "mcp")
  end

  # Decrypt OAuth token
  def decrypt_oauth_token(encrypted_value)
    return nil if encrypted_value.blank?

    Security::CredentialEncryptionService.decrypt_value(encrypted_value, namespace: "mcp")
  rescue Security::CredentialEncryptionService::DecryptionError => e
    Rails.logger.error "Failed to decrypt OAuth token for MCP server #{id}: #{e.message}"
    nil
  end

  def set_default_values
    self.status ||= "disconnected"
    self.auth_type ||= "none"
    self.args ||= []
    self.env ||= {}
    self.capabilities ||= {}
  end

  def validate_connection_configuration
    case connection_type
    when "stdio"
      if command.blank?
        errors.add(:command, "is required for stdio connection")
      end
    when "websocket", "http"
      # URL would typically be in configuration
      # Validation can be added based on your implementation
    end
  end

  def validate_args_format
    return if args.blank?

    unless args.is_a?(Array)
      errors.add(:args, "must be an array")
    end
  end

  def validate_env_format
    return if env.blank?

    unless env.is_a?(Hash)
      errors.add(:env, "must be a hash")
    end
  end

  def validate_capabilities_format
    return if capabilities.blank?

    unless capabilities.is_a?(Hash)
      errors.add(:capabilities, "must be a hash")
    end
  end

  def validate_oauth_configuration
    if oauth_client_id.blank?
      errors.add(:oauth_client_id, "is required for OAuth2 authentication")
    end
    if oauth_authorization_url.blank?
      errors.add(:oauth_authorization_url, "is required for OAuth2 authentication")
    end
    if oauth_token_url.blank?
      errors.add(:oauth_token_url, "is required for OAuth2 authentication")
    end
  end

  def initialize_connection
    # Queue connection job for async processing in worker service
    begin
      WorkerJobService.enqueue_mcp_server_connection(id, action: "connect")
      Rails.logger.info "Initialized MCP server #{name} (#{connection_type}) - queued connection job"
    rescue WorkerJobService::WorkerServiceError => e
      Rails.logger.warn "Could not queue initial connection for MCP server #{name}: #{e.message}"
      # Don't fail server creation if worker is unavailable
    end
  end

  def establish_connection
    # This is a placeholder for actual connection logic
    # Implementation would vary based on connection_type
    case connection_type
    when "stdio"
      establish_stdio_connection
    when "websocket"
      establish_websocket_connection
    when "http"
      establish_http_connection
    else
      { success: false, error: "Unknown connection type" }
    end
  end

  def establish_stdio_connection
    # Placeholder for stdio connection
    { success: true, capabilities: { "tools" => true, "resources" => true } }
  end

  def establish_websocket_connection
    # Placeholder for websocket connection
    { success: true, capabilities: { "tools" => true, "resources" => true } }
  end

  def establish_http_connection
    # Placeholder for HTTP connection
    { success: true, capabilities: { "tools" => true, "resources" => true } }
  end

  def perform_health_check
    # Placeholder for health check logic
    { healthy: true }
  end

  def fetch_tools_list
    # Placeholder for fetching tools from MCP server
    # This would make actual MCP protocol calls
    []
  end

  def calculate_uptime
    return nil unless last_health_check
    Time.current - last_health_check
  end

  def broadcast_status_change
    ActionCable.server.broadcast(
      "mcp_server_#{id}",
      {
        type: "status_change",
        server_id: id,
        status: status,
        timestamp: Time.current.iso8601
      }
    )
  end
end
