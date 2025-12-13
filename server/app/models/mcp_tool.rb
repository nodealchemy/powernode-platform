# frozen_string_literal: true

# McpTool represents an individual tool provided by an MCP server
class McpTool < ApplicationRecord
  # ==========================================
  # Associations
  # ==========================================
  belongs_to :mcp_server
  has_many :mcp_tool_executions, dependent: :destroy

  # ==========================================
  # Validations
  # ==========================================
  validates :name, presence: true
  validates :name, uniqueness: { scope: :mcp_server_id }
  validates :input_schema, presence: true
  validates :permission_level, inclusion: { in: %w[public account admin] }

  validate :validate_input_schema_format
  validate :validate_permission_fields

  # ==========================================
  # Scopes
  # ==========================================
  scope :for_server, ->(server_id) { where(mcp_server_id: server_id) }
  scope :recently_used, -> { joins(:mcp_tool_executions).where("mcp_tool_executions.created_at > ?", 24.hours.ago).distinct }
  scope :by_name, ->(name) { where(name: name) }

  # ==========================================
  # Callbacks
  # ==========================================
  before_validation :set_default_values, on: :create

  # ==========================================
  # Public Methods
  # ==========================================

  # Execute tool with parameters (with permission checking)
  def execute(user:, account:, parameters: {})
    # Validate permissions before execution
    validator = McpPermissionValidator.new(tool: self, user: user, account: account)
    unless validator.authorized?
      result = validator.authorization_result
      raise PermissionDeniedError, "Permission denied: #{result[:errors].map { |e| e[:message] }.join('; ')}"
    end

    # Create execution record
    execution = mcp_tool_executions.create!(
      user: user,
      status: "pending",
      parameters: parameters
    )

    # Execute tool asynchronously
    execute_async(execution)

    execution
  end

  # Check if user can execute this tool
  def can_execute?(user:, account:)
    validator = McpPermissionValidator.new(tool: self, user: user, account: account)
    validator.authorized?
  end

  # Get detailed authorization status for user
  def authorization_status(user:, account:)
    validator = McpPermissionValidator.new(tool: self, user: user, account: account)
    validator.authorization_result
  end

  class PermissionDeniedError < StandardError; end

  # Validate parameters against schema
  def validate_parameters(parameters)
    errors = []

    return { valid: true, errors: [] } if input_schema.blank?

    # Basic parameter validation against schema
    required_params = input_schema.dig("required") || []
    required_params.each do |param|
      unless parameters.key?(param) || parameters.key?(param.to_sym)
        errors << "Missing required parameter: #{param}"
      end
    end

    {
      valid: errors.empty?,
      errors: errors
    }
  end

  # Controller compatibility methods (for columns that don't exist yet)
  # These provide calculated values until proper database columns are added
  # Note: 'enabled' now exists as database column - removed compatibility method

  def execution_count
    mcp_tool_executions.count
  end

  def last_executed_at
    mcp_tool_executions.maximum(:created_at)
  end

  def output_schema
    {} # Default empty schema until column added
  end

  def config
    {} # Default empty config until column added
  end

  # Get tool metadata
  def metadata
    {
      name: name,
      description: description,
      server: mcp_server.name,
      input_schema: input_schema,
      execution_count: execution_count,
      recent_executions: mcp_tool_executions.order(created_at: :desc).limit(5).pluck(:status)
    }
  end

  # Get execution statistics
  def execution_stats
    total = mcp_tool_executions.count
    successful = mcp_tool_executions.where(status: "completed").count
    failed = mcp_tool_executions.where(status: "failed").count

    {
      total_executions: total,
      successful: successful,
      failed: failed,
      success_rate: total.zero? ? 0.0 : (successful.to_f / total * 100).round(2),
      avg_execution_time: calculate_avg_execution_time
    }
  end

  # ==========================================
  # Private Methods
  # ==========================================
  private

  def set_default_values
    self.input_schema ||= {}
  end

  def validate_input_schema_format
    return if input_schema.blank?

    unless input_schema.is_a?(Hash)
      errors.add(:input_schema, "must be a hash")
    end
  end

  def validate_permission_fields
    # Validate required_permissions is an array
    if required_permissions.present? && !required_permissions.is_a?(Array)
      errors.add(:required_permissions, "must be an array")
    end

    # Validate allowed_scopes structure
    if allowed_scopes.present?
      unless allowed_scopes.is_a?(Hash)
        errors.add(:allowed_scopes, "must be a hash")
        return
      end

      # Validate scope categories and permissions
      validator = McpPermissionValidator::TOOL_PERMISSION_SCOPES
      allowed_scopes.each do |category, permissions|
        unless validator.key?(category.to_sym)
          errors.add(:allowed_scopes, "invalid scope category: #{category}")
        end

        unless permissions.is_a?(Array)
          errors.add(:allowed_scopes, "permissions for #{category} must be an array")
        end
      end
    end
  end

  def execute_async(execution)
    # Queue execution job in worker service
    begin
      WorkerJobService.enqueue_mcp_tool_execution(execution.id)
      Rails.logger.info "Queued MCP tool execution job for #{name} (execution_id: #{execution.id})"
    rescue WorkerJobService::WorkerServiceError => e
      Rails.logger.error "Failed to queue MCP tool execution for #{name}: #{e.message}"
      execution.fail!("Failed to queue execution: #{e.message}")
    end
  end

  def calculate_avg_execution_time
    completed = mcp_tool_executions.where(status: "completed").where.not(execution_time_ms: nil)
    return 0 if completed.empty?

    completed.average(:execution_time_ms).to_i
  end
end
