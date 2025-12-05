# frozen_string_literal: true

class AiWorkflowTemplateInstallation < ApplicationRecord
  # Authentication & Authorization
  belongs_to :ai_workflow_template
  belongs_to :ai_workflow
  belongs_to :account
  belongs_to :installed_by_user, class_name: 'User'

  # Validations
  validates :installation_id, presence: true, uniqueness: true
  validates :template_version, presence: true
  validates :ai_workflow_template_id, uniqueness: { 
    scope: :account_id, 
    message: 'has already been installed for this account' 
  }

  # JSON columns
  attribute :customizations, :json, default: -> { {} }
  attribute :variable_mappings, :json, default: -> { {} }
  attribute :metadata, :json, default: -> { {} }

  # Scopes
  scope :recent, -> { order(created_at: :desc) }
  scope :auto_updating, -> { where(auto_update: true) }
  scope :customized, -> { where.not(customizations: {}) }
  scope :for_template, ->(template_id) { where(ai_workflow_template_id: template_id) }
  scope :for_account, ->(account_id) { where(account_id: account_id) }
  scope :by_version, ->(version) { where(template_version: version) }
  scope :outdated, -> {
    joins(:ai_workflow_template)
      .where('ai_workflow_template_installations.template_version != ai_workflow_templates.version')
  }

  # Callbacks
  before_validation :generate_installation_id, on: :create
  before_validation :capture_template_version, on: :create
  after_create :log_installation
  after_update :handle_version_updates, if: :saved_change_to_template_version?

  # Installation status methods
  def up_to_date?
    template_version == ai_workflow_template.version
  end

  def outdated?
    !up_to_date?
  end

  def auto_updating?
    auto_update?
  end

  def customized?
    customizations.present? && customizations.any?
  end

  def has_variable_mappings?
    variable_mappings.present? && variable_mappings.any?
  end

  # Template and workflow information
  def template_name
    ai_workflow_template.name
  end

  def workflow_name
    ai_workflow.name
  end

  def current_template_version
    ai_workflow_template.version
  end

  def version_difference
    return 0 if up_to_date?

    installed_version = Gem::Version.new(template_version)
    current_version = Gem::Version.new(current_template_version)
    
    current_version <=> installed_version
  end

  def version_behind_by
    return 0 if up_to_date?

    installed = template_version.split('.').map(&:to_i)
    current = current_template_version.split('.').map(&:to_i)

    # Simple calculation - in a real system you might want more sophisticated version comparison
    major_diff = current[0] - installed[0]
    minor_diff = current[1] - installed[1]
    patch_diff = current[2] - installed[2]

    {
      major: major_diff > 0 ? major_diff : 0,
      minor: minor_diff > 0 ? minor_diff : 0,
      patch: patch_diff > 0 ? patch_diff : 0
    }
  end

  # Update management
  def can_update?
    outdated? && ai_workflow_template.published?
  end

  def update_to_latest_version!(user = nil, preserve_customizations: true)
    return false unless can_update?

    updater = user || installed_by_user
    latest_version = current_template_version
    
    transaction do
      # Backup current configuration
      backup_data = {
        'previous_version' => template_version,
        'backup_timestamp' => Time.current.iso8601,
        'workflow_configuration' => ai_workflow.configuration.dup,
        'customizations_backup' => customizations.dup
      }

      # Update the workflow with new template definition
      new_definition = ai_workflow_template.workflow_definition
      
      if preserve_customizations && customizations.present?
        new_definition = apply_customizations_to_definition(new_definition)
      end

      # Update workflow
      ai_workflow.update!(
        configuration: new_definition['configuration'] || {},
        metadata: ai_workflow.metadata.merge({
          'template_updated_at' => Time.current.iso8601,
          'template_updated_by' => updater.id,
          'update_backup' => backup_data
        })
      )

      # Update installation record
      update!(
        template_version: latest_version,
        last_updated_at: Time.current,
        metadata: metadata.merge({
          'updated_to_version' => latest_version,
          'updated_at' => Time.current.iso8601,
          'updated_by' => updater.id,
          'update_history' => (metadata['update_history'] || []).push(backup_data).last(10)
        })
      )

      # Log the update
      log_update(latest_version, updater)
      
      true
    end
  rescue StandardError => e
    Rails.logger.error "Failed to update template installation #{id} to version #{latest_version}: #{e.message}"
    false
  end

  def rollback_to_previous_version!
    return false unless metadata['update_history'].present?

    latest_backup = metadata['update_history'].last
    return false unless latest_backup

    transaction do
      # Restore workflow configuration
      ai_workflow.update!(
        configuration: latest_backup['workflow_configuration'],
        metadata: ai_workflow.metadata.merge({
          'template_rolled_back_at' => Time.current.iso8601,
          'rolled_back_from_version' => template_version,
          'rolled_back_to_version' => latest_backup['previous_version']
        })
      )

      # Update installation record
      update!(
        template_version: latest_backup['previous_version'],
        customizations: latest_backup['customizations_backup'] || {},
        metadata: metadata.merge({
          'rolled_back_at' => Time.current.iso8601,
          'rolled_back_from' => template_version
        })
      )

      # Remove the backup we just used
      updated_history = metadata['update_history'].dup
      updated_history.pop
      update_column(:metadata, metadata.merge('update_history' => updated_history))

      true
    end
  rescue StandardError => e
    Rails.logger.error "Failed to rollback template installation #{id}: #{e.message}"
    false
  end

  # Customization management
  def add_customization(key, value)
    current_customizations = customizations.dup
    current_customizations[key.to_s] = value
    
    update!(
      customizations: current_customizations,
      metadata: metadata.merge({
        'last_customized_at' => Time.current.iso8601,
        'customization_count' => current_customizations.keys.size
      })
    )
  end

  def remove_customization(key)
    current_customizations = customizations.dup
    current_customizations.delete(key.to_s)
    
    update!(
      customizations: current_customizations,
      metadata: metadata.merge({
        'last_customized_at' => Time.current.iso8601,
        'customization_count' => current_customizations.keys.size
      })
    )
  end

  def customization_summary
    return {} unless customized?

    {
      total_customizations: customizations.keys.size,
      customized_fields: customizations.keys,
      last_customized: metadata['last_customized_at'],
      customization_types: categorize_customizations
    }
  end

  # Variable mapping helpers
  def map_variable(template_var, workflow_var)
    current_mappings = variable_mappings.dup
    current_mappings[template_var.to_s] = workflow_var.to_s
    
    update!(variable_mappings: current_mappings)
  end

  def unmap_variable(template_var)
    current_mappings = variable_mappings.dup
    current_mappings.delete(template_var.to_s)
    
    update!(variable_mappings: current_mappings)
  end

  def resolve_variable(template_variable_name)
    variable_mappings[template_variable_name.to_s] || template_variable_name
  end

  # Installation statistics and analytics
  def usage_statistics
    workflow_runs = ai_workflow.ai_workflow_runs
    
    {
      total_executions: workflow_runs.count,
      successful_executions: workflow_runs.where(status: 'completed').count,
      failed_executions: workflow_runs.where(status: 'failed').count,
      total_cost: workflow_runs.sum(:total_cost),
      average_execution_time: workflow_runs.where(status: 'completed').average(:duration_ms)&.to_i || 0,
      last_execution: workflow_runs.order(created_at: :desc).first&.created_at,
      success_rate: calculate_success_rate(workflow_runs)
    }
  end

  def installation_health_score
    stats = usage_statistics
    score = 100
    
    # Deduct points for failures
    if stats[:total_executions] > 0
      failure_rate = stats[:failed_executions].to_f / stats[:total_executions]
      score -= (failure_rate * 50).to_i
    end
    
    # Deduct points for being outdated
    if outdated?
      version_gap = version_behind_by
      score -= version_gap[:major] * 20 + version_gap[:minor] * 10 + version_gap[:patch] * 5
    end
    
    # Deduct points for inactivity
    if stats[:last_execution].nil? || stats[:last_execution] < 30.days.ago
      score -= 20
    end
    
    [score, 0].max
  end

  # Comparison and compatibility
  def compatibility_with_current_template
    return { compatible: true, issues: [] } if up_to_date?

    issues = []
    warnings = []
    
    current_nodes = ai_workflow_template.workflow_definition['nodes'] || []
    current_variables = ai_workflow_template.workflow_definition['variables'] || []
    
    # Check for breaking changes (simplified analysis)
    workflow_nodes = ai_workflow.ai_workflow_nodes.pluck(:node_id, :node_type)
    
    current_nodes.each do |template_node|
      matching_node = workflow_nodes.find { |wn| wn[0] == template_node['node_id'] }
      
      if matching_node.nil?
        issues << "Node '#{template_node['node_id']}' is missing from current workflow"
      elsif matching_node[1] != template_node['node_type']
        issues << "Node '#{template_node['node_id']}' type changed from #{matching_node[1]} to #{template_node['node_type']}"
      end
    end
    
    # Check variable compatibility
    workflow_variables = ai_workflow.ai_workflow_variables.pluck(:name, :variable_type)
    
    current_variables.each do |template_var|
      matching_var = workflow_variables.find { |wv| wv[0] == template_var['name'] }
      
      if matching_var && matching_var[1] != template_var['variable_type']
        warnings << "Variable '#{template_var['name']}' type changed from #{matching_var[1]} to #{template_var['variable_type']}"
      end
    end

    {
      compatible: issues.empty?,
      issues: issues,
      warnings: warnings,
      breaking_changes: issues.size,
      compatibility_score: issues.empty? ? 100 : [100 - (issues.size * 20), 0].max
    }
  end

  def installation_summary
    {
      installation_id: installation_id,
      template_name: template_name,
      workflow_name: workflow_name,
      installed_version: template_version,
      current_version: current_template_version,
      up_to_date: up_to_date?,
      auto_updating: auto_updating?,
      customized: customized?,
      health_score: installation_health_score,
      installed_at: created_at,
      last_updated: last_updated_at,
      installed_by: installed_by_user.full_name
    }
  end

  private

  def generate_installation_id
    self.installation_id = SecureRandom.uuid if installation_id.blank?
  end

  def capture_template_version
    self.template_version = ai_workflow_template.version if template_version.blank?
  end

  def apply_customizations_to_definition(definition)
    return definition unless customizations.present?

    customized_definition = definition.deep_dup
    
    customizations.each do |path, value|
      apply_customization_to_path(customized_definition, path, value)
    end
    
    customized_definition
  end

  def apply_customization_to_path(hash, path, value)
    keys = path.split('.')
    current = hash
    
    keys[0..-2].each do |key|
      current[key] ||= {}
      current = current[key]
    end
    
    current[keys.last] = value
  end

  def categorize_customizations
    categories = {
      'configuration' => 0,
      'variables' => 0,
      'nodes' => 0,
      'triggers' => 0,
      'other' => 0
    }
    
    customizations.keys.each do |key|
      case key
      when /^configuration\./
        categories['configuration'] += 1
      when /^variables\./
        categories['variables'] += 1
      when /^nodes\./
        categories['nodes'] += 1
      when /^triggers\./
        categories['triggers'] += 1
      else
        categories['other'] += 1
      end
    end
    
    categories
  end

  def calculate_success_rate(workflow_runs)
    return 0.0 if workflow_runs.empty?
    
    successful = workflow_runs.where(status: 'completed').count
    (successful.to_f / workflow_runs.count * 100).round(2)
  end

  def handle_version_updates
    if auto_update? && outdated?
      # Schedule automatic update
      AiTemplateUpdateJob.perform_later(id)
    end
  end

  def log_installation
    Rails.logger.info "Template installation created: #{ai_workflow_template.name} -> #{ai_workflow.name} (Account: #{account_id})"
    
    # Update metadata with installation info
    update_column(:metadata, metadata.merge({
      'installed_at' => created_at.iso8601,
      'installer_id' => installed_by_user_id,
      'original_template_version' => template_version
    }))
  end

  def log_update(new_version, updater)
    Rails.logger.info "Template installation updated: #{installation_id} from #{template_version} to #{new_version}"
    
    # Could also broadcast this update for real-time notifications
    # ActionCable.server.broadcast("account_#{account_id}", {
    #   type: 'template_updated',
    #   installation_id: installation_id,
    #   new_version: new_version
    # })
  end
end