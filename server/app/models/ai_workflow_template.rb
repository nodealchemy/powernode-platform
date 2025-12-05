# frozen_string_literal: true

class AiWorkflowTemplate < ApplicationRecord
  # Associations
  has_many :ai_workflow_template_installations, dependent: :destroy
  has_many :installed_workflows, through: :ai_workflow_template_installations, source: :ai_workflow
  has_many :installing_accounts, through: :ai_workflow_template_installations, source: :account

  # Validations
  validates :name, presence: true, length: { maximum: 255 }
  validates :slug, presence: true, uniqueness: true, length: { maximum: 150 },
                   format: { with: /\A[a-z0-9\-_]+\z/, message: 'can only contain lowercase letters, numbers, hyphens, and underscores' }
  validates :description, presence: true
  validates :category, presence: true, length: { maximum: 100 }
  validates :difficulty_level, presence: true, inclusion: { 
    in: %w[beginner intermediate advanced expert],
    message: 'must be a valid difficulty level'
  }
  validates :workflow_definition, presence: true
  validates :version, presence: true, format: { with: /\A\d+\.\d+\.\d+\z/, message: 'must be in semantic version format (e.g., 1.0.0)' }
  validates :usage_count, numericality: { greater_than_or_equal_to: 0 }
  validates :rating, numericality: { in: 0.0..5.0 }
  validates :rating_count, numericality: { greater_than_or_equal_to: 0 }
  validate :validate_workflow_definition_structure

  # JSON columns
  attribute :workflow_definition, :json, default: -> { {} }
  attribute :default_variables, :json, default: -> { {} }
  attribute :metadata, :json, default: -> { {} }
  attribute :tags, :json, default: -> { [] }

  # Scopes
  scope :public_templates, -> { where(is_public: true) }
  scope :featured, -> { where(is_featured: true) }
  scope :published, -> { where.not(published_at: nil) }
  scope :by_category, ->(category) { where(category: category) }
  scope :by_difficulty, ->(level) { where(difficulty_level: level) }
  scope :popular, -> { order(usage_count: :desc) }
  scope :highly_rated, -> { where('rating >= ? AND rating_count >= ?', 4.0, 5) }
  scope :recently_published, -> { order(published_at: :desc) }
  scope :search_by_text, ->(query) {
    where('name ILIKE ? OR description ILIKE ? OR long_description ILIKE ?', 
          "%#{query}%", "%#{query}%", "%#{query}%")
  }
  scope :with_tags, ->(tag_list) {
    Array(tag_list).reduce(self) do |scope, tag|
      scope.where('tags @> ?', [tag].to_json)
    end
  }
  scope :accessible_to_account, ->(account_id) {
    if account_id == 'public' || account_id.nil?
      public_templates
    else
      where(is_public: true).or(where(account_id: account_id))
    end
  }

  # Optional associations (if columns exist in schema)
  belongs_to :account, optional: true
  belongs_to :created_by_user, class_name: 'User', foreign_key: :created_by_user_id, optional: true
  belongs_to :source_workflow, class_name: 'AiWorkflow', foreign_key: :source_workflow_id, optional: true

  # Alias for controller compatibility
  has_many :installations, class_name: 'AiWorkflowTemplateInstallation', foreign_key: :ai_workflow_template_id

  # Attribute aliases for controller compatibility
  alias_attribute :template_data, :workflow_definition
  alias_attribute :install_count, :usage_count

  # Virtual attribute for visibility (maps is_public boolean to visibility string)
  def visibility
    is_public? ? 'public' : 'private'
  end

  def visibility=(value)
    self.is_public = (value.to_s == 'public')
  end

  # Permission and access control methods
  def can_edit?(user, account)
    return false unless user && account
    return true if account_id == account.id && created_by_user_id == user.id
    user.has_permission?('ai.workflows.manage') && account_id == account.id
  end

  def can_install?(account)
    return true if is_public?
    return true if account && account_id == account.id
    false
  end

  def can_publish?(user, account)
    can_edit?(user, account) && !is_public?
  end

  def install_to_account(account_id:, installed_by_user_id:, **options)
    installations.create(
      account_id: account_id,
      installed_by_user_id: installed_by_user_id,
      ai_workflow_id: options[:ai_workflow_id],
      template_version: version,
      customizations: options[:custom_configuration] || {},
      metadata: { installation_notes: options[:installation_notes] }
    )
  end

  # Callbacks
  before_validation :generate_slug, if: -> { name.present? && (slug.blank? || name_changed?) }
  before_validation :normalize_tags
  before_save :update_search_metadata
  after_create :log_template_created

  # Status and availability methods
  def published?
    published_at.present?
  end

  def public?
    is_public?
  end

  def featured?
    is_featured?
  end

  def available_for_installation?
    published? && public?
  end

  # Template content methods
  def workflow_nodes
    workflow_definition['nodes'] || []
  end

  def workflow_edges
    workflow_definition['edges'] || []
  end

  def workflow_variables
    workflow_definition['variables'] || []
  end

  def workflow_triggers
    workflow_definition['triggers'] || []
  end

  def node_count
    workflow_nodes.size
  end

  def edge_count
    workflow_edges.size
  end

  def variable_count
    workflow_variables.size
  end

  def has_ai_agents?
    workflow_nodes.any? { |node| node['node_type'] == 'ai_agent' }
  end

  def has_webhooks?
    workflow_nodes.any? { |node| node['node_type'] == 'webhook' } ||
    workflow_definition['triggers']&.any? { |trigger| trigger['trigger_type'] == 'webhook' }
  end

  def has_schedules?
    workflow_definition['triggers']&.any? { |trigger| trigger['trigger_type'] == 'schedule' }
  end

  def complexity_score
    score = 0
    
    # Base score from node count
    score += workflow_nodes.size * 2
    
    # Additional score for complex node types
    workflow_nodes.each do |node|
      case node['node_type']
      when 'ai_agent'
        score += 5
      when 'condition', 'loop', 'sub_workflow'
        score += 3
      when 'api_call', 'webhook'
        score += 2
      else
        score += 1
      end
    end
    
    # Score for edges (conditional logic adds complexity)
    workflow_edges.each do |edge|
      score += edge['is_conditional'] ? 3 : 1
    end
    
    score
  end

  # Installation and usage
  def install_for_account(account, user, customizations = {})
    return nil if ai_workflow_template_installations.exists?(account: account)

    installation = nil
    
    transaction do
      # Create workflow from template
      workflow = AiWorkflow.new.create_from_template(self, account, user, customizations)
      
      # Create installation record
      installation = ai_workflow_template_installations.create!(
        ai_workflow: workflow,
        account: account,
        installed_by: user,
        installation_id: SecureRandom.uuid,
        template_version: version,
        customizations: customizations
      )

      # Increment usage count
      increment!(:usage_count)

      # Log installation
      log_installation(account, user)
    end

    installation
  rescue StandardError => e
    Rails.logger.error "Failed to install template #{id} for account #{account.id}: #{e.message}"
    nil
  end

  def installed_by_account?(account)
    ai_workflow_template_installations.exists?(account: account)
  end

  def installation_for_account(account)
    ai_workflow_template_installations.find_by(account: account)
  end

  def recent_installations(limit = 10)
    ai_workflow_template_installations
      .includes(:account, :installed_by)
      .order(created_at: :desc)
      .limit(limit)
  end

  # Rating and feedback
  def add_rating(rating_value, account = nil)
    return false unless rating_value.between?(1, 5)

    # In a real implementation, you'd have a separate ratings table
    # For now, we'll update the aggregate rating
    new_total = (rating * rating_count) + rating_value
    new_count = rating_count + 1
    new_average = new_total / new_count

    update!(
      rating: new_average,
      rating_count: new_count,
      metadata: metadata.merge({
        'last_rated_at' => Time.current.iso8601,
        'ratings_updated' => new_count
      })
    )

    true
  end

  def rating_distribution
    # This would typically come from a separate ratings table
    # For now, return a simulated distribution
    {
      5 => (rating_count * 0.4).to_i,
      4 => (rating_count * 0.3).to_i,
      3 => (rating_count * 0.2).to_i,
      2 => (rating_count * 0.08).to_i,
      1 => (rating_count * 0.02).to_i
    }
  end

  # Template management
  def publish!
    return false if published?

    update!(
      published_at: Time.current,
      metadata: metadata.merge('published_at' => Time.current.iso8601)
    )
  end

  def unpublish!
    return false unless published?

    update!(
      published_at: nil,
      is_public: false,
      is_featured: false,
      metadata: metadata.merge('unpublished_at' => Time.current.iso8601)
    )
  end

  def feature!
    return false unless public? && published?

    update!(is_featured: true)
  end

  def unfeature!
    update!(is_featured: false)
  end

  def can_delete?(user, account)
    # Don't allow deletion if there are active installations
    return false if ai_workflow_template_installations.exists?

    # Additional permission check could be added here if needed
    # For now, allow deletion if no installations exist
    true
  end

  # Version management
  def next_version(version_type = 'patch')
    major, minor, patch = version.split('.').map(&:to_i)
    
    case version_type.to_s
    when 'major'
      "#{major + 1}.0.0"
    when 'minor'
      "#{major}.#{minor + 1}.0"
    when 'patch'
      "#{major}.#{minor}.#{patch + 1}"
    else
      "#{major}.#{minor}.#{patch + 1}"
    end
  end

  def create_new_version(new_workflow_definition, version_type = 'patch')
    new_template = self.class.new(
      name: name,
      description: description,
      long_description: long_description,
      category: category,
      difficulty_level: difficulty_level,
      workflow_definition: new_workflow_definition,
      default_variables: default_variables.deep_dup,
      metadata: metadata.deep_dup.merge('previous_version' => version),
      tags: tags.dup,
      author_name: author_name,
      author_email: author_email,
      author_url: author_url,
      license: license,
      version: next_version(version_type),
      is_public: false, # New versions start as private
      is_featured: false
    )

    new_template.save!
    new_template
  end

  # Template analytics and statistics
  def usage_statistics
    installations = ai_workflow_template_installations.includes(:ai_workflow)
    
    {
      total_installations: usage_count,
      active_installations: installations.joins(:ai_workflow).where(ai_workflows: { status: 'published' }).count,
      recent_installations: installations.where('created_at >= ?', 30.days.ago).count,
      installation_trend: calculate_installation_trend,
      top_installing_accounts: installations.group(:account_id).count.sort_by(&:last).reverse.first(5),
      average_customization_level: calculate_customization_level
    }
  end

  def performance_metrics
    workflows = installed_workflows.includes(:ai_workflow_runs)
    runs = workflows.flat_map(&:ai_workflow_runs)
    
    return {} if runs.empty?

    {
      total_executions: runs.size,
      success_rate: (runs.count { |r| r.status == 'completed' }.to_f / runs.size * 100).round(2),
      average_execution_time: runs.select { |r| r.duration_ms.present? }.sum(&:duration_ms) / runs.size,
      total_cost: runs.sum(&:total_cost),
      error_rate: (runs.count { |r| r.status == 'failed' }.to_f / runs.size * 100).round(2)
    }
  end

  # Search and discovery
  def similar_templates(limit = 5)
    self.class.public_templates
        .where.not(id: id)
        .where(category: category)
        .with_tags(tags)
        .highly_rated
        .limit(limit)
  end

  def recommended_for_account(account)
    # Basic recommendation based on account's installed templates
    installed_categories = account.ai_workflows
                                 .joins(:ai_workflow_template_installations)
                                 .joins(:ai_workflow_template)
                                 .pluck('ai_workflow_templates.category')
                                 .uniq

    self.class.public_templates
        .where.not(id: ai_workflow_template_installations.joins(:account).where(accounts: { id: account.id }).select(:ai_workflow_template_id))
        .where(category: installed_categories)
        .highly_rated
        .limit(3)
  end

  # Export and sharing
  def export_definition
    {
      template: {
        name: name,
        description: description,
        category: category,
        version: version,
        author: {
          name: author_name,
          email: author_email,
          url: author_url
        },
        license: license,
        tags: tags,
        difficulty_level: difficulty_level
      },
      workflow: workflow_definition,
      variables: default_variables,
      metadata: metadata.except('internal_stats', 'private_notes')
    }
  end

  def import_definition(definition_hash)
    template_data = definition_hash['template'] || {}
    workflow_data = definition_hash['workflow'] || {}
    variable_data = definition_hash['variables'] || {}
    
    assign_attributes(
      name: template_data['name'],
      description: template_data['description'],
      category: template_data['category'],
      workflow_definition: workflow_data,
      default_variables: variable_data,
      tags: template_data['tags'] || [],
      difficulty_level: template_data['difficulty_level'] || 'beginner',
      author_name: template_data.dig('author', 'name'),
      author_email: template_data.dig('author', 'email'),
      author_url: template_data.dig('author', 'url'),
      license: template_data['license'] || 'MIT'
    )
  end

  def to_param
    slug
  end

  private

  def generate_slug
    base_slug = name.downcase.gsub(/[^a-z0-9\s]/, '').gsub(/\s+/, '-').strip
    self.slug = ensure_unique_slug(base_slug)
  end

  def ensure_unique_slug(base_slug)
    slug_candidate = base_slug
    counter = 1

    while self.class.where(slug: slug_candidate).where.not(id: id).exists?
      slug_candidate = "#{base_slug}-#{counter}"
      counter += 1
    end

    slug_candidate
  end

  def normalize_tags
    return unless tags.is_a?(Array)

    self.tags = tags.map(&:to_s).map(&:downcase).uniq.compact
  end

  def update_search_metadata
    # Update search-related metadata
    self.metadata = metadata.merge({
      'search_keywords' => generate_search_keywords,
      'complexity_score' => complexity_score,
      'updated_at' => Time.current.iso8601
    })
  end

  def generate_search_keywords
    keywords = []
    keywords.concat(name.downcase.split)
    keywords.concat(description.downcase.split)
    keywords.concat(tags)
    keywords.concat(workflow_nodes.map { |n| n['node_type'] }.uniq)
    keywords << category.downcase
    keywords << difficulty_level
    keywords.uniq.compact
  end

  def validate_workflow_definition_structure
    return unless workflow_definition.present?

    errors.add(:workflow_definition, 'must be a hash') unless workflow_definition.is_a?(Hash)
    
    return unless workflow_definition.is_a?(Hash)

    # Validate required top-level keys
    %w[nodes edges].each do |required_key|
      unless workflow_definition.key?(required_key)
        errors.add(:workflow_definition, "must contain '#{required_key}' key")
      end
    end

    # Validate nodes structure
    nodes = workflow_definition['nodes']
    if nodes.present?
      unless nodes.is_a?(Array)
        errors.add(:workflow_definition, 'nodes must be an array')
        return
      end

      nodes.each_with_index do |node, index|
        unless node.is_a?(Hash) && node['node_id'].present? && node['node_type'].present?
          errors.add(:workflow_definition, "node #{index + 1} must have node_id and node_type")
        end
      end
    end

    # Validate edges structure
    edges = workflow_definition['edges']
    if edges.present?
      unless edges.is_a?(Array)
        errors.add(:workflow_definition, 'edges must be an array')
        return
      end

      edges.each_with_index do |edge, index|
        required_edge_keys = %w[source_node_id target_node_id]
        unless edge.is_a?(Hash) && required_edge_keys.all? { |key| edge.key?(key) }
          errors.add(:workflow_definition, "edge #{index + 1} must have source_node_id and target_node_id")
        end
      end
    end
  end

  def calculate_installation_trend
    installations_by_month = ai_workflow_template_installations
                              .where('created_at >= ?', 12.months.ago)
                              .group_by_month(:created_at)
                              .count

    return 'stable' if installations_by_month.size < 2

    recent_months = installations_by_month.values.last(3).sum
    previous_months = installations_by_month.values[-6..-4].sum

    return 'stable' if previous_months == 0

    change_rate = (recent_months - previous_months).to_f / previous_months
    
    if change_rate > 0.2
      'growing'
    elsif change_rate < -0.2
      'declining'
    else
      'stable'
    end
  end

  def calculate_customization_level
    customizations = ai_workflow_template_installations.pluck(:customizations)
    return 0.0 if customizations.empty?

    total_customization = customizations.sum do |custom|
      custom.is_a?(Hash) ? custom.keys.size : 0
    end

    (total_customization.to_f / customizations.size).round(2)
  end

  def log_template_created
    Rails.logger.info "AI Workflow Template created: #{name} (#{slug})"
  end

  def log_installation(account, user)
    Rails.logger.info "Template #{name} installed by account #{account.id} (user #{user.id})"
    
    # Update metadata with installation info
    installations_log = metadata['installations_log'] || []
    installations_log << {
      'account_id' => account.id,
      'user_id' => user.id,
      'installed_at' => Time.current.iso8601
    }

    # Keep only last 100 installations in log
    installations_log = installations_log.last(100)
    
    update_column(:metadata, metadata.merge('installations_log' => installations_log))
  end
end