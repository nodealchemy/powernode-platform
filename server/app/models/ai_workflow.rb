# frozen_string_literal: true

class AiWorkflow < ApplicationRecord
  include Auditable
  include Searchable

  # Authentication & Authorization
  belongs_to :account
  belongs_to :creator, class_name: 'User'

  # Associations
  has_many :ai_workflow_nodes, dependent: :destroy
  has_many :ai_workflow_edges, dependent: :destroy
  has_many :ai_workflow_variables, dependent: :destroy
  has_many :ai_workflow_triggers, dependent: :destroy
  has_many :ai_workflow_runs, dependent: :destroy
  has_many :ai_workflow_schedules, dependent: :destroy
  has_many :ai_workflow_template_installations, dependent: :destroy
  has_many :workflow_validations, foreign_key: :workflow_id, dependent: :destroy

  # Versioning associations
  belongs_to :parent_version, class_name: 'AiWorkflow', optional: true
  has_many :child_versions, class_name: 'AiWorkflow', foreign_key: 'parent_version_id', dependent: :nullify

  # Association aliases for convenience and test compatibility
  has_many :nodes, -> { }, class_name: 'AiWorkflowNode', foreign_key: 'ai_workflow_id', dependent: :destroy
  has_many :edges, -> { }, class_name: 'AiWorkflowEdge', foreign_key: 'ai_workflow_id', dependent: :destroy
  has_many :variables, -> { }, class_name: 'AiWorkflowVariable', foreign_key: 'ai_workflow_id', dependent: :destroy
  has_many :triggers, -> { }, class_name: 'AiWorkflowTrigger', foreign_key: 'ai_workflow_id', dependent: :destroy
  has_many :runs, -> { }, class_name: 'AiWorkflowRun', foreign_key: 'ai_workflow_id', dependent: :destroy
  has_many :schedules, -> { }, class_name: 'AiWorkflowSchedule', foreign_key: 'ai_workflow_id', dependent: :destroy
  has_many :template_installations, -> { }, class_name: 'AiWorkflowTemplateInstallation', foreign_key: 'ai_workflow_id', dependent: :destroy

  # Validations
  validates :name, presence: true, length: { minimum: 1, maximum: 255 }
  validates :description, length: { maximum: 1000 }
  validates :slug, presence: true, uniqueness: { scope: [:account_id, :version] },
                   length: { maximum: 150 },
                   format: { with: /\A[a-z0-9\-_]+\z/, message: 'can only contain lowercase letters, numbers, hyphens, and underscores' }
  validates :status, presence: true, inclusion: {
    in: %w[draft active paused inactive archived]
  }
  validates :visibility, presence: true, inclusion: {
    in: %w[private account public],
    message: 'must be a valid visibility level'
  }
  validates :configuration, presence: true
  validates :version, presence: true, format: { with: /\A\d+\.\d+\.\d+\z/, message: 'must be in semantic version format (x.y.z)' },
                     uniqueness: { scope: [:account_id, :name] }
  validates :is_active, inclusion: { in: [true, false] }
  validate :only_one_active_version_per_workflow
  validate :validate_workflow_structure
  validate :validate_template_requirements
  validate :validate_configuration_format

  # JSON columns for flexible data storage
  attribute :configuration, :json, default: -> { {} }
  attribute :metadata, :json, default: -> { {} }

  # Scopes
  scope :active, -> { where(status: 'active') }
  scope :draft, -> { where(status: 'draft') }
  scope :inactive, -> { where(status: 'inactive') }
  scope :archived, -> { where(status: 'archived') }
  scope :paused, -> { where(status: 'paused') }
  scope :templates, -> { where(is_template: true) }
  scope :workflows, -> { where(is_template: false) }
  scope :public_workflows, -> { where(visibility: 'public') }
  scope :private_workflows, -> { where(visibility: 'private') }
  scope :by_category, ->(category) { where(template_category: category) }
  scope :recently_executed, ->(days = 30) { where('last_executed_at >= ?', days.days.ago) }
  scope :search_by_text, ->(query) {
    where('name ILIKE ? OR description ILIKE ?', "%#{query}%", "%#{query}%")
  }
  
  # Additional scopes for test compatibility
  scope :executable, -> { where(status: %w[active paused]) }
  scope :by_status, ->(status_val) { where(status: status_val) }
  scope :search, ->(query) {
    return all if query.blank?
    where('name ILIKE ? OR description ILIKE ?', "%#{query}%", "%#{query}%")
  }
  scope :recent, ->(period = 1.month) { where('created_at >= ?', period.ago) }

  # Versioning scopes
  scope :active_versions, -> { where(is_active: true) }
  scope :inactive_versions, -> { where(is_active: false) }
  scope :version_family, ->(name, account_id) { where(name: name, account_id: account_id).order(:version) }
  scope :latest_version, ->(name, account_id) { version_family(name, account_id).active_versions.first }
  scope :with_active_runs, -> { joins(:ai_workflow_runs).where(ai_workflow_runs: { status: ['running', 'paused'] }).distinct }

  # Callbacks
  before_validation :generate_slug, if: -> { name.present? && (slug.blank? || name_changed?) }
  before_save :update_version_if_changed
  after_create :create_default_configuration
  after_update :update_related_schedules, if: :saved_change_to_status?

  # Status check methods
  def active?
    status == 'active'
  end

  def draft?
    status == 'draft'
  end

  def inactive?
    status == 'inactive'
  end

  def archived?
    status == 'archived'
  end

  def paused?
    status == 'paused'
  end

  # Timeout functionality for workflow execution
  def timeout_minutes
    configuration.dig('max_execution_time').to_f / 60.0 if configuration.dig('max_execution_time')
  end

  def timeout_minutes=(minutes)
    self.configuration = (configuration || {}).merge('max_execution_time' => (minutes.to_f * 60).to_i)
  end

  def timeout_seconds
    configuration.dig('max_execution_time') || 3600 # Default 1 hour
  end

  def can_execute?
    (active? || paused?) && has_valid_structure? && ai_workflow_nodes.any?
  end

  def can_edit?
    %w[draft paused].include?(status)
  end

  def can_delete?
    # Don't allow deletion if there are running or pending executions
    return false if ai_workflow_runs.where(status: %w[pending running initializing]).exists?

    # Don't allow deletion if there are recent executions (within last 5 minutes)
    return false if ai_workflow_runs.where('created_at > ?', 5.minutes.ago).exists?

    true
  end

  # Workflow structure methods
  def has_valid_structure?
    # Only require at least one start node
    # End nodes are optional - workflows can terminate naturally
    start_nodes.any? && !has_circular_dependencies?
  end

  # Public validation method for API endpoint
  # Returns validation result hash with errors and warnings
  def validate_structure
    validation_errors = []
    validation_warnings = []

    # Check for at least one start node
    if start_nodes.empty?
      validation_errors << 'Workflow must have at least one node marked as a start node'
    end

    # Check for circular dependencies (excluding intentional loops)
    if has_circular_dependencies?
      validation_errors << 'Workflow contains circular dependencies'
    end

    # Check if workflow has any nodes
    if ai_workflow_nodes.empty?
      validation_errors << 'Workflow must contain at least one node'
    end

    # Warnings for best practices
    if end_nodes.empty? && ai_workflow_nodes.any?
      validation_warnings << 'Workflow has no end nodes - execution will terminate when no next nodes are available'
    end

    # Check for orphaned nodes (nodes not connected to anything)
    if ai_workflow_nodes.any? && ai_workflow_edges.any?
      connected_node_ids = Set.new
      ai_workflow_edges.each do |edge|
        connected_node_ids.add(edge.source_node_id)
        connected_node_ids.add(edge.target_node_id)
      end

      orphaned_nodes = ai_workflow_nodes.reject { |node| connected_node_ids.include?(node.node_id) }
      if orphaned_nodes.any? && orphaned_nodes.size < ai_workflow_nodes.size
        orphaned_names = orphaned_nodes.map(&:name).join(', ')
        validation_warnings << "Orphaned nodes detected (not connected to workflow): #{orphaned_names}"
      end
    end

    # Check for unreachable nodes from start nodes
    if start_nodes.any? && ai_workflow_edges.any?
      reachable_nodes = find_reachable_nodes
      unreachable_nodes = ai_workflow_nodes.reject { |node| reachable_nodes.include?(node.node_id) }

      if unreachable_nodes.any?
        unreachable_names = unreachable_nodes.map(&:name).join(', ')
        validation_warnings << "Unreachable nodes detected (cannot be reached from start nodes): #{unreachable_names}"
      end
    end

    {
      valid: validation_errors.empty?,
      errors: validation_errors,
      warnings: validation_warnings
    }
  end

  def start_nodes
    ai_workflow_nodes.where(is_start_node: true)
  end

  def end_nodes
    ai_workflow_nodes.where(is_end_node: true)
  end

  def node_count
    ai_workflow_nodes.count
  end

  def edge_count
    ai_workflow_edges.count
  end

  # Execution methods
  def execute(input_variables: {}, user: nil, trigger: nil, trigger_type: 'manual', trigger_context: {})
    raise ArgumentError, 'Workflow is not in a state that can be executed' unless can_execute?

    run_metadata = trigger_context.present? ? { trigger_context: trigger_context } : {}

    # Use database transaction with row-level locking to prevent race conditions
    transaction do
      # Lock this workflow record to prevent concurrent executions
      reload(lock: true)

      # Check for very recent pending/running executions (within last 3 seconds)
      recent_runs = ai_workflow_runs.where(
        'created_at > ? AND status IN (?)',
        3.seconds.ago,
        ['pending', 'running', 'initializing']
      ).order(:created_at)

      if recent_runs.exists?
        # If there's a very recent pending/running execution, return it instead of creating duplicate
        existing_run = recent_runs.first
        Rails.logger.info "Preventing duplicate execution for workflow #{id}. Recent run exists: #{existing_run.run_id} (created #{Time.current - existing_run.created_at} seconds ago)"
        return existing_run
      end

      run = ai_workflow_runs.build(
        account: account,
        triggered_by_user: user || creator,
        ai_workflow_trigger: trigger,
        trigger_type: trigger_type,
        input_variables: input_variables,
        total_nodes: node_count,
        runtime_context: build_execution_context,
        metadata: run_metadata
      )

      if run.save
        # Queue async execution via worker service API
        begin
          WorkerJobService.enqueue_ai_workflow_execution(run.run_id, {
            'realtime' => true,
            'channel_id' => "ai_workflow_execution_#{run.run_id}"
          })
        rescue StandardError => e
          Rails.logger.error "Failed to enqueue workflow execution: #{e.message}"
          # Still return the run even if enqueueing fails - it can be retried
        end

        update_column(:last_executed_at, Time.current)
        increment!(:execution_count)
        run
      else
        raise ActiveRecord::RecordInvalid, run
      end
    end
  end

  def execution_summary
    recent_runs = ai_workflow_runs.limit(100)
    
    {
      total_executions: execution_count,
      recent_executions: recent_runs.count,
      success_rate: calculate_success_rate(recent_runs),
      average_duration: calculate_average_duration(recent_runs),
      last_execution: last_executed_at,
      total_cost: recent_runs.sum(:total_cost),
      status_breakdown: recent_runs.group(:status).count
    }
  end

  # Template methods
  def create_from_template(template, account, user, customizations = {})
    transaction do
      # Create workflow from template
      workflow_data = template.workflow_definition.deep_dup
      workflow_data.merge!(customizations)

      new_workflow = account.ai_workflows.create!(
        name: customizations['name'] || "#{template.name} (Copy)",
        description: customizations['description'] || template.description,
        creator: user,
        configuration: workflow_data['configuration'] || {},
        metadata: workflow_data['metadata']&.merge('template_id' => template.id) || { 'template_id' => template.id },
        status: 'draft'
      )

      # Create nodes from template
      if workflow_data['nodes'].present?
        workflow_data['nodes'].each do |node_data|
          new_workflow.ai_workflow_nodes.create!(
            node_id: node_data['node_id'],
            node_type: node_data['node_type'],
            name: node_data['name'],
            description: node_data['description'],
            position: node_data['position'] || {},
            configuration: node_data['configuration'] || {},
            validation_rules: node_data['validation_rules'] || {},
            metadata: node_data['metadata'] || {},
            is_start_node: node_data['is_start_node'] || false,
            is_end_node: node_data['is_end_node'] || false
          )
        end
      end

      # Create edges from template
      if workflow_data['edges'].present?
        workflow_data['edges'].each do |edge_data|
          new_workflow.ai_workflow_edges.create!(
            edge_id: edge_data['edge_id'],
            source_node_id: edge_data['source_node_id'],
            target_node_id: edge_data['target_node_id'],
            source_handle: edge_data['source_handle'],
            target_handle: edge_data['target_handle'],
            edge_type: edge_data['edge_type'] || 'default',
            condition: edge_data['condition'] || {},
            configuration: edge_data['configuration'] || {},
            is_conditional: edge_data['is_conditional'] || false
          )
        end
      end

      # Create variables from template
      if workflow_data['variables'].present?
        workflow_data['variables'].each do |var_data|
          new_workflow.ai_workflow_variables.create!(
            name: var_data['name'],
            variable_type: var_data['variable_type'] || 'string',
            description: var_data['description'],
            default_value: var_data['default_value'],
            validation_rules: var_data['validation_rules'] || {},
            is_required: var_data['is_required'] || false,
            is_input: var_data['is_input'] || false,
            is_output: var_data['is_output'] || false
          )
        end
      end

      # Record template installation
      installation = template.ai_workflow_template_installations.create!(
        ai_workflow: new_workflow,
        account: account,
        installed_by: user,
        installation_id: SecureRandom.uuid,
        template_version: template.version,
        customizations: customizations
      )

      # Update template usage count
      template.increment!(:usage_count)

      new_workflow
    end
  end

  def publish!
    return false unless can_edit? && has_valid_structure?

    update!(
      status: 'active',
      published_at: Time.current,
      version: increment_version(version)
    )
  end

  def archive!
    update!(
      status: 'archived',
      metadata: metadata.merge('archived_at' => Time.current.iso8601)
    )
  end

  def pause!
    update!(
      status: 'paused',
      metadata: metadata.merge('paused_at' => Time.current.iso8601)
    )
  end

  def duplicate(target_account = nil, user = nil)
    target_account ||= account
    user ||= creator
    duplicate_for_account(target_account, user)
  end

  def duplicate_for_account(target_account, user)
    transaction do
      new_workflow = self.class.new(
        account: target_account,
        creator: user,
        name: "#{name} (Copy)",
        description: description,
        configuration: configuration.deep_dup,
        metadata: metadata.deep_dup.merge(
          'duplicated_from' => id,
          'duplicated_at' => Time.current.iso8601
        ),
        visibility: 'private',
        status: 'draft'
      )

      new_workflow.save!

      # Duplicate nodes with new node IDs
      node_id_mapping = {}
      ai_workflow_nodes.each do |node|
        new_node_id = SecureRandom.uuid
        node_id_mapping[node.node_id] = new_node_id
        
        new_workflow.ai_workflow_nodes.create!(
          node_id: new_node_id,
          node_type: node.node_type,
          name: node.name,
          description: node.description,
          position: node.position.dup,
          configuration: node.configuration.deep_dup,
          validation_rules: node.validation_rules.deep_dup,
          metadata: node.metadata.deep_dup,
          is_start_node: node.is_start_node,
          is_end_node: node.is_end_node,
          is_error_handler: node.is_error_handler,
          error_node_id: node.error_node_id,
          timeout_seconds: node.timeout_seconds,
          retry_count: node.retry_count
        )
      end

      # Duplicate edges with mapped node IDs  
      ai_workflow_edges.each do |edge|
        new_workflow.ai_workflow_edges.create!(
          edge_id: SecureRandom.uuid,
          source_node_id: node_id_mapping[edge.source_node_id],
          target_node_id: node_id_mapping[edge.target_node_id],
          source_handle: edge.source_handle,
          target_handle: edge.target_handle,
          edge_type: edge.edge_type,
          condition: edge.condition.deep_dup,
          configuration: edge.configuration.deep_dup,
          metadata: edge.metadata.deep_dup,
          is_conditional: edge.is_conditional,
          priority: edge.priority
        )
      end

      # Duplicate variables
      ai_workflow_variables.each do |variable|
        new_workflow.ai_workflow_variables.create!(
          name: variable.name,
          variable_type: variable.variable_type,
          description: variable.description,
          default_value: variable.default_value.deep_dup,
          validation_rules: variable.validation_rules.deep_dup,
          metadata: variable.metadata.deep_dup,
          is_required: variable.is_required,
          is_input: variable.is_input,
          is_output: variable.is_output,
          is_secret: variable.is_secret,
          scope: variable.scope
        )
      end

      new_workflow
    end
  end

  def self.import_from_data(import_data, target_account, user, name_override: nil)
    transaction do
      workflow_data = import_data[:workflow] || import_data['workflow']
      nodes_data = import_data[:nodes] || import_data['nodes'] || []
      edges_data = import_data[:edges] || import_data['edges'] || []

      workflow = create!(
        account: target_account,
        creator: user,
        name: name_override || workflow_data[:name] || workflow_data['name'],
        description: workflow_data[:description] || workflow_data['description'],
        status: workflow_data[:status] || workflow_data['status'] || 'draft',
        visibility: workflow_data[:visibility] || workflow_data['visibility'] || 'private',
        configuration: workflow_data[:configuration] || workflow_data['configuration'] || {}
      )

      # Import nodes
      node_id_mapping = {}
      nodes_data.each do |node_data|
        old_node_id = node_data[:node_id] || node_data['node_id']
        new_node_id = SecureRandom.uuid
        new_node = workflow.ai_workflow_nodes.create!(
          node_id: new_node_id,
          node_type: node_data[:node_type] || node_data['node_type'],
          name: node_data[:name] || node_data['name'],
          position: node_data[:position] || node_data['position'] || {},
          configuration: node_data[:configuration] || node_data['configuration'] || {},
          is_start_node: node_data[:is_start_node] || node_data['is_start_node'] || false,
          is_end_node: node_data[:is_end_node] || node_data['is_end_node'] || false
        )
        node_id_mapping[old_node_id] = new_node.node_id
      end

      # Import edges with updated node IDs
      edges_data.each do |edge_data|
        old_source = edge_data[:source_node_id] || edge_data['source_node_id']
        old_target = edge_data[:target_node_id] || edge_data['target_node_id']

        workflow.ai_workflow_edges.create!(
          edge_id: SecureRandom.uuid,
          source_node_id: node_id_mapping[old_source],
          target_node_id: node_id_mapping[old_target],
          edge_type: edge_data[:edge_type] || edge_data['edge_type'] || 'default',
          configuration: edge_data[:configuration] || edge_data['configuration'] || {}
        )
      end

      workflow
    end
  end

  def to_param
    slug
  end

  def display_name
    name
  end

  # Statistics and metrics methods
  def execution_stats
    all_runs = ai_workflow_runs.limit(100)
    completed_runs = all_runs.where(status: 'completed')
    
    failed_runs = all_runs.where(status: 'failed')
    
    {
      total_executions: all_runs.count,
      successful_executions: completed_runs.count,
      failed_executions: failed_runs.count,
      completed_runs: completed_runs.count,
      failed_runs: failed_runs.count,
      success_rate: calculate_success_rate_for_runs(all_runs),
      avg_execution_time: calculate_average_duration_for_runs(completed_runs),
      average_execution_time: calculate_average_duration_for_runs(completed_runs),
      total_cost: completed_runs.sum(:total_cost)
    }
  end

  def recent_runs(period = 24.hours)
    ai_workflow_runs.where('created_at >= ?', period.ago)
  end

  def total_cost
    ai_workflow_runs.where(status: 'completed').sum(:total_cost)
  end

  def average_execution_time
    completed_runs = ai_workflow_runs.where(status: 'completed').where.not(duration_ms: nil)
    return 0.0 if completed_runs.empty?

    completed_runs.average(:duration_ms).to_f
  end

  # Versioning methods
  def version_manager
    @version_manager ||= Mcp::WorkflowVersionManager.new(
      workflow: self,
      account: account,
      user: creator
    )
  end

  def create_new_version(changes:, change_summary: nil)
    version_manager.create_version(changes: changes, change_summary: change_summary)
  end

  def version_history
    version_manager.version_history
  end

  def has_active_runs?
    ai_workflow_runs.where(status: ['running', 'paused']).exists?
  end

  def all_versions
    self.class.version_family(name, account_id)
  end

  def latest_active_version
    all_versions.active_versions.first
  end

  def is_latest_version?
    self == latest_active_version
  end

  def version_number
    Gem::Version.new(version)
  end

  def newer_than?(other_workflow)
    version_number > Gem::Version.new(other_workflow.version)
  end

  private

  def generate_slug
    base_slug = name.downcase.gsub(/[^a-z0-9\s]/, '').gsub(/\s+/, '-').strip
    self.slug = ensure_unique_slug(base_slug)
  end

  def ensure_unique_slug(base_slug)
    return base_slug if account.nil?
    
    slug_candidate = base_slug
    counter = 1

    while account.ai_workflows.where(slug: slug_candidate).where.not(id: id).exists?
      slug_candidate = "#{base_slug}-#{counter}"
      counter += 1
    end

    slug_candidate
  end

  def update_version_if_changed
    if configuration_changed? && persisted?
      self.version = increment_version(version)
    end
  end

  def increment_version(current_version)
    major, minor, patch = current_version.split('.').map(&:to_i)
    "#{major}.#{minor}.#{patch + 1}"
  end

  def create_default_configuration
    return if configuration.present?

    default_config = {
      'execution_mode' => 'sequential',
      'timeout_seconds' => 3600,
      'max_parallel_nodes' => 5,
      'auto_retry' => false,
      'error_handling' => 'stop',
      'notifications' => {
        'on_completion' => false,
        'on_error' => true
      }
    }

    update_column(:configuration, default_config)
  end

  def update_related_schedules
    if paused? || archived?
      ai_workflow_schedules.where(is_active: true).update_all(
        is_active: false,
        status: 'disabled'
      )
    end
  end

  def only_one_active_version_per_workflow
    return unless is_active?
    return unless account_id && name

    existing_active = self.class.where(
      account_id: account_id,
      name: name,
      is_active: true
    ).where.not(id: id).exists?

    if existing_active
      errors.add(:is_active, "only one version of '#{name}' can be active at a time")
    end
  end

  def validate_workflow_structure
    # Skip validation during bulk node updates - wait for explicit validation
    return if @bulk_updating_nodes

    return unless ai_workflow_nodes.loaded? || ai_workflow_nodes.any?

    # Validate at least one start node
    if start_nodes.empty?
      errors.add(:base, 'Workflow must have at least one node marked as a start node')
    end

    # End nodes are optional - workflows can terminate naturally
    # Multiple end nodes are allowed for different termination paths
    # No validation needed for end nodes

    errors.add(:base, 'Workflow contains circular dependencies') if has_circular_dependencies?
  end

  def validate_template_requirements
    return unless is_template?

    errors.add(:template_category, 'must be present for templates') if template_category.blank?
    errors.add(:description, 'must be present for templates') if description.blank?
  end

  def validate_configuration_format
    return if configuration.blank?
    
    unless configuration.is_a?(Hash)
      errors.add(:configuration, 'must be a hash')
      return
    end

    # Validate execution_mode if present
    if configuration['execution_mode'].present?
      valid_modes = %w[sequential parallel conditional batch]
      unless valid_modes.include?(configuration['execution_mode'])
        errors.add(:configuration, 'invalid execution_mode')
      end
    end

    # Validate max_execution_time if present
    if configuration['max_execution_time'].present?
      max_time = configuration['max_execution_time'].to_i
      if max_time <= 0
        errors.add(:configuration, 'max_execution_time must be positive')
      end
    end
  end

  def has_circular_dependencies?
    # Cycle detection that allows intentional loops and branching/merging patterns
    # Intentional loops include:
    # - Edges explicitly typed as: retry, loop, compensation
    # - Edges from condition nodes that create feedback loops (revision patterns)
    # - Edges that go "backwards" to enable iteration/retry workflows
    #
    # Uses Kahn's algorithm (topological sort) which properly handles DAGs with
    # multiple paths that reconverge - these are NOT cycles.

    # Build adjacency list and in-degree count
    in_degree = Hash.new(0)
    adjacency = Hash.new { |h, k| h[k] = [] }

    # Get all node IDs and build node info map
    all_node_ids = ai_workflow_nodes.pluck(:node_id).to_set
    node_types = ai_workflow_nodes.pluck(:node_id, :node_type).to_h

    # Initialize in_degree for all nodes
    all_node_ids.each { |id| in_degree[id] = 0 }

    # Identify nodes that can have intentional feedback loops
    # (condition, loop, split nodes can create valid revision/retry patterns)
    feedback_source_types = %w[condition loop split].freeze

    # Build the graph, excluding intentional loop edges
    ai_workflow_edges.each do |edge|
      next unless all_node_ids.include?(edge.source_node_id) && all_node_ids.include?(edge.target_node_id)

      # Skip edges explicitly marked as intentional loops
      next if %w[retry loop compensation feedback revision].include?(edge.edge_type)

      # Skip "false" branch edges from condition nodes - these often create valid feedback loops
      # A condition node returning "false" to retry/revise is a common workflow pattern
      source_type = node_types[edge.source_node_id]
      if feedback_source_types.include?(source_type)
        # Check if this edge goes to an earlier node (feedback pattern)
        # by checking source_handle - false/retry paths are intentional loops
        next if edge.source_handle.to_s.match?(/false|retry|loop|back|revision/i)
      end

      adjacency[edge.source_node_id] << edge.target_node_id
      in_degree[edge.target_node_id] += 1
    end

    # Kahn's algorithm: start with nodes that have no incoming edges
    queue = all_node_ids.select { |id| in_degree[id] == 0 }
    processed_count = 0

    while queue.any?
      node_id = queue.shift
      processed_count += 1

      adjacency[node_id].each do |neighbor|
        in_degree[neighbor] -= 1
        queue << neighbor if in_degree[neighbor] == 0
      end
    end

    # If we couldn't process all nodes, there's a real cycle
    # (not just reconvergent branching paths or intentional feedback loops)
    processed_count < all_node_ids.size
  end

  def calculate_success_rate(runs)
    return 0.0 if runs.empty?
    
    successful = runs.where(status: 'completed').count
    (successful.to_f / runs.count * 100).round(2)
  end

  def calculate_average_duration(runs)
    completed_runs = runs.where(status: 'completed').where.not(duration_ms: nil)
    return 0 if completed_runs.empty?
    
    completed_runs.average(:duration_ms).to_i
  end

  def calculate_success_rate_for_runs(runs)
    return 0.0 if runs.empty?
    
    successful = runs.where(status: 'completed').count
    (successful.to_f / runs.count * 100).round(2)
  end

  def calculate_average_duration_for_runs(runs)
    return 0.0 if runs.empty?
    
    completed_with_duration = runs.where.not(duration_ms: nil)
    return 0.0 if completed_with_duration.empty?
    
    completed_with_duration.average(:duration_ms).to_f
  end

  def build_execution_context
    {
      workflow_version: version,
      node_count: node_count,
      edge_count: edge_count,
      configuration_snapshot: configuration,
      created_at: Time.current.iso8601
    }
  end

  # Find all nodes reachable from start nodes
  def find_reachable_nodes
    reachable = Set.new
    queue = start_nodes.map(&:node_id)

    while queue.any?
      current_node_id = queue.shift
      next if reachable.include?(current_node_id)

      reachable.add(current_node_id)

      # Find all outgoing edges from this node
      outgoing_edges = ai_workflow_edges.where(source_node_id: current_node_id)
      outgoing_edges.each do |edge|
        queue << edge.target_node_id unless reachable.include?(edge.target_node_id)
      end
    end

    reachable
  end
end