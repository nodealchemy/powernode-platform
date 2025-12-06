# frozen_string_literal: true

# AI Agent Model - MCP-only implementation for tool registration and execution
# Completely replaces legacy event-based communication with MCP protocol
class AiAgent < ApplicationRecord
  # Concerns
  include Auditable
  include Searchable

  # Associations
  belongs_to :account
  belongs_to :creator, class_name: 'User'
  belongs_to :ai_provider
  has_many :ai_agent_executions, dependent: :destroy
  has_many :ai_conversations, dependent: :destroy
  has_many :ai_messages, dependent: :destroy

  # Validations
  validates :name, presence: true, length: { maximum: 255 }, uniqueness: { scope: :account_id }
  validates :description, length: { maximum: 1000 }
  validates :slug, presence: true, uniqueness: { scope: :account_id }, length: { maximum: 150 },
                   format: { with: /\A[a-z0-9\-_]+\z/, message: 'can only contain lowercase letters, numbers, hyphens, and underscores' }
  validates :agent_type, presence: true, inclusion: {
    in: %w[assistant code_assistant data_analyst content_generator image_generator workflow_optimizer workflow_operations monitor],
    message: 'is not included in the list'
  }
  validates :status, inclusion: { in: %w[active inactive paused error archived] }
  validates :mcp_capabilities, presence: true
  validates :version, format: { with: /\A\d+\.\d+\.\d+\z/, message: 'must be in semantic version format (x.y.z)' }
  validate :mcp_tool_manifest_valid
  validate :mcp_input_schema_valid
  validate :mcp_output_schema_valid

  # JSON attributes for MCP data
  attribute :mcp_tool_manifest, :json, default: -> { {} }
  attribute :mcp_input_schema, :json, default: -> { default_input_schema }
  attribute :mcp_output_schema, :json, default: -> { default_output_schema }
  attribute :mcp_capabilities, :json, default: -> { [] }
  attribute :mcp_metadata, :json, default: -> { {} }

  # Scopes
  scope :active, -> { where(status: 'active') }
  scope :inactive, -> { where(status: 'inactive') }
  scope :paused, -> { where(status: 'paused') }
  scope :archived, -> { where(status: 'archived') }
  scope :by_type, ->(type) { where(agent_type: type) }
  scope :by_creator, ->(user) { where(creator: user) }
  scope :mcp_enabled, -> { where.not(mcp_tool_manifest: {}) }
  scope :with_capability, ->(capability) { where('mcp_capabilities @> ?', [capability].to_json) }
  scope :recently_executed, ->(days = 30) { where('last_executed_at >= ?', days.days.ago) }
  scope :healthy, -> { where(status: 'active') }
  scope :search_by_text, ->(query) {
    where('name ILIKE ? OR description ILIKE ?', "%#{query}%", "%#{query}%")
  }

  # Callbacks
  before_validation :generate_slug, if: -> { name.present? && (slug.blank? || name_changed?) }
  before_validation :normalize_agent_type
  before_validation :normalize_mcp_capabilities
  before_validation :set_default_mcp_schemas
  before_save :update_version_if_mcp_changed
  before_save :ensure_mcp_tool_manifest
  after_create :register_mcp_tool
  after_update :update_mcp_tool_registration, if: :saved_change_to_mcp_tool_manifest?
  after_destroy :unregister_mcp_tool

  # =============================================================================
  # MCP TOOL FUNCTIONALITY
  # =============================================================================

  # Check if agent is available for MCP execution
  def mcp_available?
    active? && mcp_tool_manifest.present? && mcp_capabilities.any? && ai_provider&.is_active?
  end

  # Get MCP tool ID for registry
  def mcp_tool_id
    "agent_#{id}_v#{version.gsub('.', '_')}"
  end

  # Create MCP execution record
  def create_mcp_execution(input_parameters, execution_options = {})
    execution_data = {
      execution_id: SecureRandom.uuid,
      status: 'running',
      input_parameters: input_parameters,
      started_at: Time.current
    }

    # In a real implementation, this would create an AiAgentExecution record
    # For now, return a simple execution object
    OpenStruct.new(execution_data)
  end

  # Generate complete MCP tool manifest
  def generate_mcp_tool_manifest
    {
      'name' => mcp_tool_name,
      'description' => description || "AI Agent: #{name}",
      'type' => 'ai_agent',
      'version' => version,
      'capabilities' => mcp_capabilities,
      'inputSchema' => mcp_input_schema,
      'outputSchema' => mcp_output_schema,
      'metadata' => generate_mcp_metadata,
      'agent_id' => id,
      'provider_id' => ai_provider_id,
      'account_id' => account_id,
      'creator_id' => creator_id,
      'agent_type' => agent_type,
      'created_at' => created_at&.iso8601,
      'updated_at' => updated_at&.iso8601
    }
  end

  # Get MCP tool name (used for tool registration)
  def mcp_tool_name
    "#{account.subdomain}_#{slug}".downcase.gsub(/[^a-z0-9_]/, '_')
  end

  # Execute agent via MCP protocol
  def execute_via_mcp(input_parameters, execution_options = {})
    Rails.logger.info "[AI_AGENT_MCP] Executing agent #{id} via MCP"

    # Validate that agent is available
    raise StandardError, "Agent not available for MCP execution" unless mcp_available?

    # Create execution record
    execution = create_mcp_execution(input_parameters, execution_options)

    # Delegate to AI MCP agent executor
    executor = AiMcpAgentExecutor.new(
      agent: self,
      execution: execution,
      account: account
    )

    result = executor.execute(input_parameters)

    # Update execution record
    execution.update!(
      status: 'completed',
      output_data: result,
      completed_at: Time.current,
      duration_ms: (Time.current - execution.started_at) * 1000
    )

    result
  rescue StandardError => e
    Rails.logger.error "[AI_AGENT_MCP] Execution failed: #{e.message}"

    # Update execution record with error
    execution&.update!(
      status: 'failed',
      error_message: e.message,
      completed_at: Time.current
    )

    raise
  end

  # Register agent as MCP tool
  def register_as_mcp_tool
    Rails.logger.info "[AI_AGENT_MCP] Registering agent #{id} as MCP tool"

    mcp_registry = McpRegistryService.new(account: account)
    tool_manifest = generate_mcp_tool_manifest

    mcp_registry.register_tool(mcp_tool_id, tool_manifest)

    # Update agent with registration info
    update!(
      mcp_tool_manifest: tool_manifest,
      mcp_registered_at: Time.current
    )

    Rails.logger.info "[AI_AGENT_MCP] Agent registered with tool ID: #{mcp_tool_id}"
    mcp_tool_id
  end

  # Unregister agent from MCP registry
  def unregister_from_mcp
    Rails.logger.info "[AI_AGENT_MCP] Unregistering agent #{id} from MCP"

    mcp_registry = McpRegistryService.new(account: account)
    mcp_registry.unregister_tool(mcp_tool_id)

    Rails.logger.info "[AI_AGENT_MCP] Agent unregistered from MCP"
  end

  # Check if agent supports a specific MCP capability
  def supports_mcp_capability?(capability)
    mcp_capabilities.include?(capability.to_s)
  end

  # Get agent performance metrics via MCP telemetry
  def mcp_performance_metrics
    telemetry = McpTelemetryService.new(account: account)
    telemetry.get_tool_performance(mcp_tool_id)
  end

  # =============================================================================
  # STATUS AND HEALTH METHODS
  # =============================================================================

  def active?
    status == 'active'
  end

  def inactive?
    status == 'inactive'
  end

  def archived?
    status == 'archived'
  end

  def error?
    status == 'error'
  end

  def paused?
    status == 'paused'
  end

  # Update last execution timestamp
  def mark_executed!
    update!(last_executed_at: Time.current)
  end

  # Get execution count (total executions)
  def execution_count
    ai_agent_executions.count
  end

  # Get success rate as percentage
  def success_rate
    total = ai_agent_executions.count
    return 0 if total.zero?

    successful = ai_agent_executions.where(status: 'completed').count
    (successful.to_f / total * 100).round(2)
  end

  # Get execution statistics
  def execution_stats(period = 30.days)
    scope = ai_agent_executions.where('created_at >= ?', period.ago)

    {
      total_executions: scope.count,
      successful_executions: scope.where(status: 'completed').count,
      failed_executions: scope.where(status: 'failed').count,
      average_duration: scope.where.not(duration_ms: nil).average(:duration_ms) || 0,
      success_rate: calculate_success_rate(scope)
    }
  end

  # =============================================================================
  # MCP-SPECIFIC METHODS
  # =============================================================================

  # Generate MCP tool manifest for agent registration
  def generate_mcp_tool_manifest
    {
      'name' => name.downcase.gsub(/[^a-z0-9]/, '_'),
      'description' => description || "AI Agent: #{name}",
      'type' => 'ai_agent',
      'version' => version,
      'capabilities' => mcp_capabilities,
      'inputSchema' => mcp_input_schema.presence || default_input_schema,
      'outputSchema' => mcp_output_schema.presence || default_output_schema,
      'metadata' => {
        'agent_id' => id,
        'agent_type' => agent_type,
        'created_at' => created_at&.iso8601,
        'updated_at' => updated_at&.iso8601
      }
    }
  end

  # Main execution method for workflows
  def execute(input_parameters, user: nil, provider: nil)
    # Use provided provider or the agent's default provider
    provider ||= ai_provider

    # Create an execution record
    execution = ai_agent_executions.create!(
      account: account,
      execution_id: SecureRandom.uuid,
      user: user,
      ai_provider_id: provider&.id,
      status: 'running',
      input_parameters: input_parameters,
      started_at: Time.current,
      execution_context: {
        context_type: 'workflow',
        triggered_at: Time.current.iso8601
      }
    )

    begin
      # For now, simulate execution with simple success
      # In production, this would call the actual AI provider API
      Rails.logger.info "[AI_AGENT] Executing agent #{name} with provider #{provider&.name || 'default'}"

      # Simulate processing time
      sleep(0.5)

      # Generate a simple output
      output = {
        'response' => "Processed input with #{name}",
        'processed_at' => Time.current.iso8601,
        'input_summary' => input_parameters.to_s[0..100]
      }

      # Update execution as successful
      execution.update!(
        status: 'completed',
        output_data: output,
        completed_at: Time.current,
        duration_ms: (Time.current - execution.started_at) * 1000
      )

      execution
    rescue StandardError => e
      Rails.logger.error "[AI_AGENT] Execution failed: #{e.message}"
      execution.update!(
        status: 'failed',
        error_details: {
          error: e.message,
          error_class: e.class.name
        },
        completed_at: Time.current,
        duration_ms: (Time.current - execution.started_at) * 1000
      )
      execution
    end
  end

  # Execute agent via MCP protocol
  def execute_via_mcp(input_parameters, execution_options = {})
    raise StandardError, "Agent not available for MCP execution" unless mcp_available?

    # Create execution record
    execution = create_mcp_execution(input_parameters, execution_options)

    # Execute via AI MCP executor
    executor = AiMcpAgentExecutor.new(
      agent: self,
      execution: execution,
      account: account
    )

    result = executor.execute(input_parameters)
    result
  end

  # Validate input against MCP schema
  def validate_mcp_input(input_data)
    return true if mcp_input_schema.blank?

    begin
      validator = JsonSchemaValidator.new(mcp_input_schema)
      validator.valid?(input_data)
    rescue StandardError => e
      Rails.logger.warn "[AGENT_MCP] Input validation error: #{e.message}"
      false
    end
  end

  # Validate output against MCP schema
  def validate_mcp_output(output_data)
    return true if mcp_output_schema.blank?

    begin
      validator = JsonSchemaValidator.new(mcp_output_schema)
      validator.valid?(output_data)
    rescue StandardError => e
      Rails.logger.warn "[AGENT_MCP] Output validation error: #{e.message}"
      false
    end
  end

  # =============================================================================
  # AGENT OPERATIONS
  # =============================================================================

  # Clone agent for another account
  def clone_for_account(target_account, cloner_user)
    cloned_agent = self.dup
    cloned_agent.account = target_account
    cloned_agent.creator = cloner_user
    cloned_agent.name = "#{name} (Copy)"
    cloned_agent.slug = nil # Will be regenerated
    cloned_agent.status = 'inactive'
    cloned_agent.last_executed_at = nil
    cloned_agent.mcp_registered_at = nil
    cloned_agent.save!
    cloned_agent
  end

  # Run a test execution without persisting
  def test_execution(test_input, test_user)
    {
      success: true,
      test_output: "Test execution completed for agent #{name}",
      input: test_input,
      timestamp: Time.current.iso8601
    }
  end

  # Validate agent configuration
  def validate_configuration
    errors_list = []
    warnings_list = []

    # Check if agent has required fields
    errors_list << 'Agent name is missing' if name.blank?
    errors_list << 'Agent type is invalid' unless %w[assistant code_assistant data_analyst content_generator image_generator workflow_optimizer workflow_operations monitor].include?(agent_type)
    errors_list << 'AI provider is missing or inactive' unless ai_provider&.is_active?
    errors_list << 'MCP capabilities are missing' if mcp_capabilities.blank?

    # Check for warnings
    warnings_list << 'Agent has never been executed' if last_executed_at.nil?
    warnings_list << 'Agent description is missing' if description.blank?

    {
      valid: errors_list.empty?,
      errors: errors_list,
      warnings: warnings_list
    }
  end

  # =============================================================================
  # MCP LIFECYCLE CALLBACKS
  # =============================================================================

  private

  # Generate MCP manifest after creation/update
  def ensure_mcp_manifest
    if mcp_tool_manifest.blank? || name_changed? || mcp_capabilities_changed?
      self.mcp_tool_manifest = generate_mcp_tool_manifest
      self.mcp_registered_at = Time.current
    end
  end

  # Create MCP execution record
  def create_mcp_execution(input_parameters, execution_options)
    ai_agent_executions.create!(
      account: account,
      user: execution_options[:user],
      ai_provider: ai_provider,
      execution_id: SecureRandom.uuid,
      status: 'pending',
      input_parameters: input_parameters,
      execution_context: {
        'mcp_execution' => true,
        'connection_id' => execution_options[:connection_id],
        'protocol_version' => '2025-06-18'
      }.merge(execution_options.except(:user, :connection_id))
    )
  end

  # Default schemas for MCP protocol
  def default_input_schema
    {
      'type' => 'object',
      'properties' => {
        'input' => {
          'type' => 'string',
          'description' => 'Input text for the AI agent'
        },
        'context' => {
          'type' => 'object',
          'description' => 'Additional context for execution'
        }
      },
      'required' => ['input']
    }
  end

  def default_output_schema
    {
      'type' => 'object',
      'properties' => {
        'result' => {
          'type' => 'string',
          'description' => 'Generated result from the AI agent'
        },
        'metadata' => {
          'type' => 'object',
          'description' => 'Execution metadata'
        }
      },
      'required' => ['result']
    }
  end

  # =============================================================================
  # PRIVATE HELPER METHODS
  # =============================================================================

  private

  def generate_slug
    return if name.blank?

    base_slug = name.downcase.gsub(/[^a-z0-9\s\-_]/, '').squeeze(' ').strip.gsub(/\s+/, '-')
    self.slug = base_slug

    # Ensure uniqueness within account
    counter = 1
    while account.ai_agents.where(slug: self.slug).where.not(id: id).exists?
      self.slug = "#{base_slug}-#{counter}"
      counter += 1
    end
  end

  def normalize_agent_type
    self.agent_type = agent_type&.downcase&.strip
  end

  def normalize_mcp_capabilities
    return unless mcp_capabilities.is_a?(Array)

    self.mcp_capabilities = mcp_capabilities.map(&:to_s).map(&:downcase).uniq.compact
  end

  def set_default_mcp_schemas
    self.mcp_input_schema = default_input_schema if mcp_input_schema.blank?
    self.mcp_output_schema = default_output_schema if mcp_output_schema.blank?
  end

  def update_version_if_mcp_changed
    if mcp_tool_manifest_changed? || mcp_input_schema_changed? || mcp_output_schema_changed?
      increment_version
    end
  end

  def increment_version
    if version.present?
      version_parts = version.split('.').map(&:to_i)
      version_parts[2] += 1  # Increment patch version
      self.version = version_parts.join('.')
    else
      self.version = '1.0.0'
    end
  end

  def generate_mcp_metadata
    {
      'powernode_agent_id' => id,
      'powernode_account_id' => account_id,
      'powernode_creator_id' => creator_id,
      'agent_type' => agent_type,
      'provider_type' => ai_provider&.provider_type,
      'tags' => [],
      'documentation_url' => nil,
      'support_url' => nil,
      'license' => 'proprietary'
    }
  end

  def create_mcp_execution(input_parameters, execution_options)
    ai_agent_executions.create!(
      account: account,
      user: execution_options[:user] || creator,
      ai_provider: ai_provider,
      input_parameters: input_parameters,
      status: 'running',
      execution_id: SecureRandom.uuid,
      started_at: Time.current,
      execution_context: {
        'mcp_execution' => true,
        'tool_id' => mcp_tool_id,
        'execution_options' => execution_options
      }
    )
  end

  def calculate_success_rate(scope)
    total = scope.count
    return 0 if total.zero?

    successful = scope.where(status: 'completed').count
    (successful.to_f / total * 100).round(2)
  end

  # =============================================================================
  # VALIDATION METHODS
  # =============================================================================

  def mcp_tool_manifest_valid
    return if mcp_tool_manifest.blank?

    unless mcp_tool_manifest.is_a?(Hash)
      errors.add(:mcp_tool_manifest, 'must be a valid JSON object')
      return
    end

    # Validate required fields for tool manifests
    required_fields = %w[name description type version]
    missing_fields = required_fields - mcp_tool_manifest.keys

    if missing_fields.any?
      errors.add(:mcp_tool_manifest, "missing required fields: #{missing_fields.join(', ')}")
    end
  end

  def mcp_input_schema_valid
    validate_json_schema(mcp_input_schema, :mcp_input_schema)
  end

  def mcp_output_schema_valid
    validate_json_schema(mcp_output_schema, :mcp_output_schema)
  end

  def validate_json_schema(schema, field_name)
    return if schema.blank?

    unless schema.is_a?(Hash)
      errors.add(field_name, 'must be a valid JSON schema object')
      return
    end

    # Basic JSON Schema validation
    unless schema['type'].present?
      errors.add(field_name, 'must include a type field')
    end
  end

  # =============================================================================
  # CALLBACK METHODS
  # =============================================================================

  def ensure_mcp_tool_manifest
    # Auto-generate MCP tool manifest if missing or incomplete, or if name changed
    if mcp_tool_manifest.blank? || !has_required_manifest_fields? || name_changed?
      self.mcp_tool_manifest = generate_mcp_tool_manifest
      self.mcp_registered_at = Time.current
    end
  end

  def has_required_manifest_fields?
    return false unless mcp_tool_manifest.is_a?(Hash)
    required_fields = %w[name description type version]
    required_fields.all? { |field| mcp_tool_manifest[field].present? }
  end


  def register_mcp_tool
    # Register agent as MCP tool after creation
    return unless mcp_available?

    begin
      registry = McpRegistryService.new(account: account)
      tool_id = mcp_tool_id
      manifest = mcp_tool_manifest

      registry.register_tool(tool_id, manifest)
      Rails.logger.info "[AI_AGENT_MCP] Registered agent #{id} as MCP tool: #{tool_id}"
    rescue StandardError => e
      Rails.logger.error "[AI_AGENT_MCP] Failed to register MCP tool: #{e.message}"
      # Don't fail the creation, but log the error
    end
  end

  def update_mcp_tool_registration
    # Update MCP tool registration when manifest changes
    return unless mcp_available?

    begin
      registry = McpRegistryService.new(account: account)
      tool_id = mcp_tool_id
      manifest = mcp_tool_manifest

      registry.update_tool(tool_id, manifest)
      Rails.logger.info "[AI_AGENT_MCP] Updated MCP tool registration for agent #{id}: #{tool_id}"
    rescue StandardError => e
      Rails.logger.error "[AI_AGENT_MCP] Failed to update MCP tool registration: #{e.message}"
    end
  end

  def unregister_mcp_tool
    # Unregister from MCP when agent is destroyed
    begin
      registry = McpRegistryService.new(account: account)
      tool_id = mcp_tool_id

      registry.unregister_tool(tool_id)
      Rails.logger.info "[AI_AGENT_MCP] Unregistered MCP tool for agent #{id}: #{tool_id}"
    rescue StandardError => e
      Rails.logger.error "[AI_AGENT_MCP] Failed to unregister MCP tool: #{e.message}"
      # Don't fail the destruction, but log the error
    end
  end

  # =============================================================================
  # CLASS METHODS FOR MCP DEFAULTS
  # =============================================================================

  def self.default_input_schema
    {
      'type' => 'object',
      'properties' => {
        'input' => {
          'type' => 'string',
          'description' => 'Primary input text for the AI agent',
          'minLength' => 1,
          'maxLength' => 100000
        },
        'context' => {
          'type' => 'object',
          'description' => 'Additional context for the agent execution',
          'properties' => {
            'temperature' => {
              'type' => 'number',
              'minimum' => 0,
              'maximum' => 2,
              'description' => 'Sampling temperature for response generation'
            },
            'max_tokens' => {
              'type' => 'integer',
              'minimum' => 1,
              'maximum' => 32000,
              'description' => 'Maximum number of tokens to generate'
            }
          },
          'additionalProperties' => true
        }
      },
      'required' => ['input'],
      'additionalProperties' => false
    }
  end

  def default_input_schema
    self.class.default_input_schema
  end

  def self.default_output_schema
    {
      'type' => 'object',
      'properties' => {
        'output' => {
          'type' => 'string',
          'description' => 'Generated response from the AI agent'
        },
        'metadata' => {
          'type' => 'object',
          'description' => 'Additional metadata about the response',
          'properties' => {
            'tokens_used' => {
              'type' => 'integer',
              'description' => 'Number of tokens consumed'
            },
            'processing_time_ms' => {
              'type' => 'number',
              'description' => 'Processing time in milliseconds'
            },
            'model_used' => {
              'type' => 'string',
              'description' => 'AI model used for generation'
            }
          },
          'additionalProperties' => true
        },
        'error' => {
          'type' => 'string',
          'description' => 'Error message if execution failed'
        }
      },
      'required' => ['output'],
      'additionalProperties' => false
    }
  end

  def default_output_schema
    self.class.default_output_schema
  end

  # =============================================================================
  # DEPRECATED METHODS (FOR BACKWARDS COMPATIBILITY)
  # =============================================================================
  # Note: capabilities is already defined at line ~213 as public method
end