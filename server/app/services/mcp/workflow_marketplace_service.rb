# frozen_string_literal: true

module Mcp
  # Workflow Marketplace Service
  # Provides template discovery, recommendations, and marketplace functionality
  class WorkflowMarketplaceService
    attr_reader :account, :user

    def initialize(account:, user: nil)
      @account = account
      @user = user
    end

    # Template discovery and search
    def discover_templates(filters = {})
      scope = Ai::WorkflowTemplate.public_templates.published

      # Apply filters
      scope = apply_search_filters(scope, filters)

      # Apply sorting
      scope = apply_sorting(scope, filters[:sort_by])

      # Return paginated results
      {
        templates: scope.limit(filters[:limit] || 20).offset(filters[:offset] || 0),
        total_count: scope.count,
        filters_applied: filters,
        recommendations: get_recommendations_for_account(limit: 3)
      }
    end

    # Advanced search with multiple criteria
    def advanced_search(criteria)
      scope = Ai::WorkflowTemplate.public_templates.published

      # Text search
      if criteria[:query].present?
        scope = scope.search_by_text(criteria[:query])
      end

      # Category filter
      if criteria[:categories].present?
        scope = scope.where(category: criteria[:categories])
      end

      # Difficulty filter
      if criteria[:difficulty_levels].present?
        scope = scope.where(difficulty_level: criteria[:difficulty_levels])
      end

      # Tag filter
      if criteria[:tags].present?
        scope = scope.with_tags(criteria[:tags])
      end

      # Complexity filter
      if criteria[:min_complexity].present? || criteria[:max_complexity].present?
        scope = filter_by_complexity(scope, criteria[:min_complexity], criteria[:max_complexity])
      end

      # Feature filters
      scope = scope.select { |t| t.has_ai_agents? } if criteria[:has_ai_agents]
      scope = scope.select { |t| t.has_webhooks? } if criteria[:has_webhooks]
      scope = scope.select { |t| t.has_schedules? } if criteria[:has_schedules]

      # Rating filter
      if criteria[:min_rating].present?
        scope = scope.where("rating >= ?", criteria[:min_rating])
      end

      # Usage filter
      if criteria[:min_usage].present?
        scope = scope.where("usage_count >= ?", criteria[:min_usage])
      end

      build_search_results(scope, criteria)
    end

    # AI-powered template recommendations
    def get_recommendations_for_account(limit: 5)
      recommendations = []

      # 1. Based on installed templates (collaborative filtering)
      similar_based = recommend_based_on_installed_templates(limit: 2)
      recommendations.concat(similar_based)

      # 2. Based on workflow execution patterns
      pattern_based = recommend_based_on_execution_patterns(limit: 2)
      recommendations.concat(pattern_based)

      # 3. Trending templates
      if recommendations.size < limit
        trending = recommend_trending_templates(limit: limit - recommendations.size)
        recommendations.concat(trending)
      end

      recommendations.uniq.first(limit).map do |template|
        {
          template: template,
          recommendation_score: calculate_recommendation_score(template),
          recommendation_reasons: generate_recommendation_reasons(template)
        }
      end
    end

    # Template analytics and insights
    def template_analytics(template_id)
      template = Ai::WorkflowTemplate.find(template_id)

      {
        overview: {
          total_installations: template.usage_count,
          rating: template.rating,
          rating_count: template.rating_count,
          category: template.category,
          difficulty: template.difficulty_level
        },
        usage_stats: template.usage_statistics,
        performance: template.performance_metrics,
        installation_trend: analyze_installation_trend(template),
        user_feedback: aggregate_user_feedback(template),
        similar_templates: template.similar_templates(5)
      }
    end

    # Template installation with validation
    def install_template(template_id, customizations = {})
      template = Ai::WorkflowTemplate.find(template_id)

      # Validate installation eligibility
      validation = validate_installation(template)
      return { success: false, errors: validation[:errors] } unless validation[:valid]

      # Check if already installed
      if template.subscribed_by_account?(account)
        return {
          success: false,
          errors: [ "Template already installed for this account" ]
        }
      end

      # Perform installation
      installation = template.install_for_account(account, user, customizations)

      if installation
        # Broadcast installation event
        broadcast_installation_event(template, installation)

        {
          success: true,
          installation: installation,
          workflow: installation.workflow,
          message: "Template '#{template.name}' successfully installed"
        }
      else
        {
          success: false,
          errors: [ "Installation failed. Please try again." ]
        }
      end
    end

    # Template rating and feedback
    def rate_template(template_id, rating_value, feedback = {})
      template = Ai::WorkflowTemplate.find(template_id)

      # Validate user has installed the template
      unless template.subscribed_by_account?(account)
        return {
          success: false,
          error: "You must install the template before rating it"
        }
      end

      # Add rating
      if template.add_rating(rating_value, account)
        # Store feedback if provided
        if feedback.present?
          store_template_feedback(template, rating_value, feedback)
        end

        {
          success: true,
          new_rating: template.rating,
          rating_count: template.rating_count,
          message: "Thank you for your feedback!"
        }
      else
        {
          success: false,
          error: "Invalid rating value (must be 1-5)"
        }
      end
    end

    # Template comparison
    def compare_templates(template_ids)
      return { error: "Provide 2-5 templates to compare" } unless template_ids.size.between?(2, 5)

      templates = Ai::WorkflowTemplate.where(id: template_ids)

      {
        templates: templates.map { |t| template_comparison_data(t) },
        comparison_matrix: build_comparison_matrix(templates),
        recommendation: recommend_best_fit(templates)
      }
    end

    # Category and tag exploration
    def explore_categories
      categories = Ai::WorkflowTemplate.public_templates.published
                                     .group(:category)
                                     .count
                                     .sort_by { |_, count| -count }

      categories.map do |category, count|
        {
          category: category,
          template_count: count,
          top_templates: Ai::WorkflowTemplate.public_templates
                                          .published
                                          .by_category(category)
                                          .highly_rated
                                          .limit(3),
          average_rating: calculate_category_average_rating(category)
        }
      end
    end

    def explore_tags
      all_tags = Ai::WorkflowTemplate.public_templates.published.pluck(:tags).flatten.uniq

      all_tags.map do |tag|
        templates_with_tag = Ai::WorkflowTemplate.public_templates
                                              .published
                                              .with_tags([ tag ])

        {
          tag: tag,
          template_count: templates_with_tag.count,
          average_rating: templates_with_tag.average(:rating)&.round(2) || 0.0,
          top_templates: templates_with_tag.highly_rated.limit(3)
        }
      end.sort_by { |t| -t[:template_count] }
    end

    # Marketplace statistics
    def marketplace_statistics
      {
        total_templates: Ai::WorkflowTemplate.public_templates.published.count,
        total_installations: Ai::WorkflowTemplate.sum(:usage_count),
        total_categories: Ai::WorkflowTemplate.distinct.pluck(:category).size,
        featured_templates: Ai::WorkflowTemplate.featured.count,
        average_rating: Ai::WorkflowTemplate.public_templates.average(:rating)&.round(2) || 0.0,
        most_popular: Ai::WorkflowTemplate.public_templates.popular.first(5),
        highest_rated: Ai::WorkflowTemplate.public_templates.highly_rated.limit(5),
        recently_published: Ai::WorkflowTemplate.recently_published.limit(5),
        trending_categories: trending_categories,
        marketplace_growth: calculate_marketplace_growth
      }
    end

    # User's installed templates dashboard
    def my_templates_dashboard
      installations = Ai::WorkflowTemplateInstallation.where(account: account)
                                                    .includes(:ai_workflow_template, :ai_workflow)

      {
        total_installed: installations.count,
        up_to_date: installations.count(&:up_to_date?),
        outdated: installations.count(&:outdated?),
        auto_updating: installations.count(&:auto_updating?),
        customized: installations.count(&:customized?),
        installations: installations.map do |installation|
          {
            installation: installation,
            summary: installation.installation_summary,
            health_score: installation.installation_health_score,
            usage_stats: installation.usage_statistics,
            update_available: installation.outdated?,
            compatibility: installation.compatibility_with_current_template
          }
        end,
        recommendations: get_recommendations_for_account(limit: 3)
      }
    end

    # Template update management
    def check_for_updates
      installations = Ai::WorkflowTemplateInstallation.where(account: account).outdated

      installations.map do |installation|
        {
          installation_id: installation.installation_id,
          template_name: installation.template_name,
          current_version: installation.template_version,
          latest_version: installation.current_template_version,
          version_gap: installation.version_behind_by,
          auto_update_enabled: installation.auto_updating?,
          compatibility: installation.compatibility_with_current_template,
          can_update: installation.can_update?
        }
      end
    end

    def update_all_templates(options = {})
      installations = Ai::WorkflowTemplateInstallation.where(account: account).outdated

      results = installations.map do |installation|
        next unless installation.can_update?

        success = installation.update_to_latest_version!(
          user,
          preserve_customizations: options[:preserve_customizations] != false
        )

        {
          installation_id: installation.installation_id,
          template_name: installation.template_name,
          success: success,
          new_version: success ? installation.template_version : nil
        }
      end.compact

      {
        total_attempted: results.size,
        successful: results.count { |r| r[:success] },
        failed: results.count { |r| !r[:success] },
        results: results
      }
    end

    # Template publishing (for template creators)
    def publish_template(workflow_id, template_metadata)
      workflow = account.ai_workflows.find(workflow_id)

      # Create template from workflow
      template = Ai::WorkflowTemplate.new(
        name: template_metadata[:name] || workflow.name,
        description: template_metadata[:description],
        long_description: template_metadata[:long_description],
        category: template_metadata[:category],
        difficulty_level: template_metadata[:difficulty_level] || "intermediate",
        workflow_definition: build_template_definition(workflow),
        default_variables: extract_workflow_variables(workflow),
        tags: template_metadata[:tags] || [],
        author_name: user&.full_name || account.name,
        author_email: user&.email,
        author_url: template_metadata[:author_url],
        license: template_metadata[:license] || "MIT",
        version: template_metadata[:version] || "1.0.0",
        is_public: template_metadata[:is_public] || false,
        metadata: {
          source_workflow_id: workflow.id,
          source_account_id: account.id,
          created_from_marketplace: true
        }
      )

      if template.save
        # Publish if requested
        template.publish! if template_metadata[:publish_immediately]

        {
          success: true,
          template: template,
          message: "Template '#{template.name}' created successfully"
        }
      else
        {
          success: false,
          errors: template.errors.full_messages
        }
      end
    end

    private

    def apply_search_filters(scope, filters)
      scope = scope.by_category(filters[:category]) if filters[:category].present?
      scope = scope.by_difficulty(filters[:difficulty]) if filters[:difficulty].present?
      scope = scope.with_tags(filters[:tags]) if filters[:tags].present?
      scope = scope.featured if filters[:featured]
      scope = scope.highly_rated if filters[:highly_rated]
      scope
    end

    def apply_sorting(scope, sort_by)
      case sort_by&.to_sym
      when :popular
        scope.popular
      when :rating
        scope.order(rating: :desc)
      when :recent
        scope.recently_published
      when :name
        scope.order(:name)
      else
        scope.recently_published
      end
    end

    def filter_by_complexity(scope, min, max)
      scope.select do |template|
        score = template.complexity_score
        (min.nil? || score >= min) && (max.nil? || score <= max)
      end
    end

    def build_search_results(scope, criteria)
      {
        templates: scope.is_a?(ActiveRecord::Relation) ? scope : scope.to_a,
        total_count: scope.is_a?(ActiveRecord::Relation) ? scope.count : scope.size,
        criteria: criteria,
        suggestions: generate_search_suggestions(criteria)
      }
    end

    def recommend_based_on_installed_templates(limit:)
      installed_templates = account.ai_workflows
                                   .joins(:ai_workflow_template_installations)
                                   .pluck("workflow_template_installations.workflow_template_id")

      return [] if installed_templates.empty?

      # Find templates in same categories as installed ones
      installed_categories = Ai::WorkflowTemplate.where(id: installed_templates)
                                              .pluck(:category)
                                              .uniq

      Ai::WorkflowTemplate.public_templates
                       .published
                       .where.not(id: installed_templates)
                       .where(category: installed_categories)
                       .highly_rated
                       .limit(limit)
    end

    def recommend_based_on_execution_patterns(limit:)
      # Analyze workflow execution patterns
      recent_runs = account.ai_workflows
                          .joins(:workflow_runs)
                          .where("ai_workflow_runs.created_at >= ?", 30.days.ago)
                          .group("ai_workflows.id")
                          .having("COUNT(ai_workflow_runs.id) > 5")
                          .pluck("ai_workflows.id")

      return [] if recent_runs.empty?

      # Find templates that complement frequently used workflows
      Ai::WorkflowTemplate.public_templates
                       .published
                       .highly_rated
                       .limit(limit)
    end

    def recommend_trending_templates(limit:)
      # Find templates with increasing installation rates
      Ai::WorkflowTemplate.public_templates
                       .published
                       .where("usage_count >= ?", 10)
                       .order(Arel.sql("usage_count * rating DESC"))
                       .limit(limit)
    end

    def calculate_recommendation_score(template)
      score = 0

      # Rating contribution (40%)
      score += (template.rating / 5.0 * 40)

      # Usage contribution (30%)
      normalized_usage = [ template.usage_count.to_f / 100, 1.0 ].min
      score += (normalized_usage * 30)

      # Recency contribution (20%)
      days_since_publish = (Time.current - template.published_at).to_i / 1.day
      recency_score = [ 1.0 - (days_since_publish / 365.0), 0.0 ].max
      score += (recency_score * 20)

      # Category match (10%)
      installed_categories = account.ai_workflows
                                   .joins(:ai_workflow_template_installations)
                                   .joins(ai_workflow_template_installations: :ai_workflow_template)
                                   .pluck("workflow_templates.category")
                                   .uniq

      score += 10 if installed_categories.include?(template.category)

      score.round(2)
    end

    def generate_recommendation_reasons(template)
      reasons = []

      if template.rating >= 4.5
        reasons << "Highly rated (#{template.rating}/5.0)"
      end

      if template.usage_count >= 50
        reasons << "Popular with #{template.usage_count}+ installations"
      end

      installed_categories = account.ai_workflows
                                   .joins(:ai_workflow_template_installations)
                                   .joins(ai_workflow_template_installations: :ai_workflow_template)
                                   .pluck("workflow_templates.category")
                                   .uniq

      if installed_categories.include?(template.category)
        reasons << "Matches your interests in #{template.category}"
      end

      if template.published_at >= 30.days.ago
        reasons << "Recently published"
      end

      reasons
    end

    def analyze_installation_trend(template)
      installations = template.workflow_template_installations
                             .where("created_at >= ?", 6.months.ago)
                             .group_by_month(:created_at)
                             .count

      {
        monthly_installations: installations,
        trend: template.send(:calculate_installation_trend),
        growth_rate: calculate_growth_rate(installations)
      }
    end

    def calculate_growth_rate(monthly_data)
      return 0.0 if monthly_data.size < 2

      recent_avg = monthly_data.values.last(3).sum / 3.0
      previous_avg = monthly_data.values[-6..-4].sum / 3.0

      return 0.0 if previous_avg.zero?

      ((recent_avg - previous_avg) / previous_avg * 100).round(2)
    end

    def aggregate_user_feedback(template)
      # In a real implementation, this would aggregate from a feedback table
      {
        rating_distribution: template.rating_distribution,
        total_reviews: template.rating_count,
        average_rating: template.rating,
        sentiment: calculate_sentiment(template.rating)
      }
    end

    def calculate_sentiment(rating)
      case rating
      when 4.5..5.0 then "Very Positive"
      when 4.0...4.5 then "Positive"
      when 3.0...4.0 then "Mixed"
      when 2.0...3.0 then "Negative"
      else "Very Negative"
      end
    end

    def validate_installation(template)
      errors = []

      errors << "Template is not published" unless template.published?
      errors << "Template is not public" unless template.public?
      errors << "Account already has this template installed" if template.subscribed_by_account?(account)

      {
        valid: errors.empty?,
        errors: errors
      }
    end

    def broadcast_installation_event(template, installation)
      # Broadcast to account channel
      ActionCable.server.broadcast(
        "account_#{account.id}",
        {
          type: "template_installed",
          template_id: template.id,
          template_name: template.name,
          installation_id: installation.installation_id,
          timestamp: Time.current.iso8601
        }
      )
    end

    def store_template_feedback(template, rating, feedback)
      # In a real implementation, store in a dedicated feedback table
      template.update(
        metadata: template.metadata.merge(
          "recent_feedback" => (template.metadata["recent_feedback"] || []).push({
            "account_id" => account.id,
            "rating" => rating,
            "feedback" => feedback,
            "created_at" => Time.current.iso8601
          }).last(50)
        )
      )
    end

    def template_comparison_data(template)
      {
        id: template.id,
        name: template.name,
        category: template.category,
        difficulty: template.difficulty_level,
        rating: template.rating,
        usage_count: template.usage_count,
        complexity_score: template.complexity_score,
        node_count: template.node_count,
        has_ai_agents: template.has_ai_agents?,
        has_webhooks: template.has_webhooks?,
        has_schedules: template.has_schedules?,
        performance: template.performance_metrics
      }
    end

    def build_comparison_matrix(templates)
      attributes = %i[rating usage_count complexity_score node_count]

      matrix = {}
      attributes.each do |attr|
        matrix[attr] = templates.map { |t| [ t.id, t.send(attr) ] }.to_h
      end

      matrix
    end

    def recommend_best_fit(templates)
      # Simple scoring based on rating and usage
      best = templates.max_by { |t| (t.rating * 0.6) + (t.usage_count * 0.4 / 100.0) }

      {
        template_id: best.id,
        template_name: best.name,
        reason: "Highest combination of rating and popularity"
      }
    end

    def calculate_category_average_rating(category)
      Ai::WorkflowTemplate.public_templates
                       .published
                       .by_category(category)
                       .average(:rating)
                       &.round(2) || 0.0
    end

    def trending_categories
      recent_installations = Ai::WorkflowTemplateInstallation
                              .where("created_at >= ?", 30.days.ago)
                              .joins(:ai_workflow_template)
                              .group("workflow_templates.category")
                              .count
                              .sort_by { |_, count| -count }
                              .first(5)

      recent_installations.map do |category, count|
        {
          category: category,
          recent_installations: count,
          total_templates: Ai::WorkflowTemplate.by_category(category).count
        }
      end
    end

    def calculate_marketplace_growth
      total_installations = Ai::WorkflowTemplateInstallation
                             .where("created_at >= ?", 12.months.ago)
                             .group_by_month(:created_at)
                             .count

      {
        monthly_installations: total_installations,
        growth_rate: calculate_growth_rate(total_installations)
      }
    end

    def generate_search_suggestions(criteria)
      suggestions = []

      # Suggest related tags
      if criteria[:tags].present?
        related_templates = Ai::WorkflowTemplate.public_templates.with_tags(criteria[:tags])
        all_tags = related_templates.pluck(:tags).flatten.uniq - criteria[:tags]
        suggestions << { type: "tags", items: all_tags.first(5) } if all_tags.any?
      end

      # Suggest related categories
      if criteria[:categories].present?
        # Find categories commonly installed together
        # This is a simplified version
        suggestions << { type: "categories", items: [] }
      end

      suggestions
    end

    def build_template_definition(workflow)
      {
        nodes: workflow.workflow_nodes.map do |node|
          {
            node_id: node.node_id,
            node_type: node.node_type,
            name: node.name,
            position: node.position,
            configuration: node.configuration
          }
        end,
        edges: workflow.workflow_edges.map do |edge|
          {
            edge_id: edge.edge_id,
            source_node_id: edge.source_node_id,
            target_node_id: edge.target_node_id,
            is_conditional: edge.is_conditional,
            condition: edge.condition
          }
        end,
        variables: workflow.workflow_variables.map do |var|
          {
            name: var.name,
            variable_type: var.variable_type,
            default_value: var.default_value,
            is_required: var.is_required
          }
        end,
        triggers: workflow.workflow_triggers.map do |trigger|
          {
            trigger_id: trigger.trigger_id,
            trigger_type: trigger.trigger_type,
            configuration: trigger.configuration
          }
        end
      }
    end

    def extract_workflow_variables(workflow)
      workflow.workflow_variables.each_with_object({}) do |var, hash|
        hash[var.name] = {
          type: var.variable_type,
          default_value: var.default_value,
          description: var.description,
          is_required: var.is_required
        }
      end
    end
  end
end
