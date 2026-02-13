# frozen_string_literal: true

module Ai
  class MarketplaceService
    attr_reader :account

    # Cache TTLs
    CATEGORIES_CACHE_TTL = 1.hour
    FEATURED_TEMPLATES_CACHE_TTL = 15.minutes
    SEARCH_CACHE_TTL = 5.minutes

    def initialize(account)
      @account = account
    end

    # Publisher Management
    def create_publisher(name:, user:, description: nil, website_url: nil, support_email: nil)
      return { error: "Enterprise feature required" } unless defined?(PowernodeEnterprise::Engine)

      Ai::PublisherAccount.create!(
        account: account,
        primary_user: user,
        publisher_name: name,
        description: description,
        website_url: website_url,
        support_email: support_email,
        status: "pending",
        verification_status: "unverified"
      )
    end

    def get_publisher
      return nil unless defined?(PowernodeEnterprise::Engine)

      Ai::PublisherAccount.find_by(account: account)
    end

    # Template Management
    def create_template(publisher:, name:, description:, category:, vertical: nil, agent_config: {}, pricing_type: "free", price_usd: nil)
      Ai::AgentTemplate.create!(
        publisher: publisher,
        name: name,
        description: description,
        category: category,
        vertical: vertical,
        agent_config: agent_config,
        pricing_type: pricing_type,
        price_usd: price_usd,
        status: "draft",
        visibility: "private"
      )
    end

    def publish_template(template)
      return { success: false, error: "Template not found" } unless template
      return { success: false, error: "Publisher not verified" } unless template.publisher.can_publish?

      template.publish!
      { success: true, template: template }
    end

    def search_templates(query: nil, category: nil, vertical: nil, pricing_type: nil, page: 1, per_page: 20)
      templates = Ai::AgentTemplate.published.public_templates

      if query.present?
        sanitized = ActiveRecord::Base.sanitize_sql_like(query)
        templates = templates.where("name ILIKE ? OR description ILIKE ?", "%#{sanitized}%", "%#{sanitized}%")
      end
      templates = templates.by_category(category) if category.present?
      templates = templates.by_vertical(vertical) if vertical.present?
      templates = templates.where(pricing_type: pricing_type) if pricing_type.present?

      templates.includes(:publisher).order(installation_count: :desc).page(page).per(per_page)
    end

    def featured_templates(limit: 10)
      cache_key = "ai:marketplace:featured:#{limit}"

      Rails.cache.fetch(cache_key, expires_in: FEATURED_TEMPLATES_CACHE_TTL) do
        Ai::AgentTemplate.published.public_templates.featured.limit(limit).to_a
      end
    end

    # Installation Management
    def install_template(template:, user:, custom_config: {})
      return { success: false, error: "Template not available" } unless template.published?

      existing = Ai::AgentInstallation.find_by(account: account, agent_template: template)
      return { success: false, error: "Already installed" } if existing&.active?

      # Handle payment if required
      if template.requires_payment?
        payment_result = process_template_payment(template)
        return payment_result unless payment_result[:success]
      end

      installation = Ai::AgentInstallation.create!(
        account: account,
        agent_template: template,
        installed_by: user,
        status: "active",
        installed_version: template.version,
        custom_config: custom_config,
        license_type: template.free? ? "standard" : "standard"
      )

      # Create the agent from template
      agent = create_agent_from_template(template, installation, custom_config, user)
      installation.update!(installed_agent: agent) if agent

      { success: true, installation: installation, agent: agent }
    end

    def uninstall_template(installation)
      return { success: false, error: "Installation not found" } unless installation

      installation.cancel!
      { success: true }
    end

    # Reviews
    def create_review(template:, user:, rating:, title: nil, content: nil, pros: [], cons: [])
      installation = Ai::AgentInstallation.find_by(account: account, agent_template: template)

      review = Ai::AgentReview.create!(
        agent_template: template,
        account: account,
        user: user,
        installation: installation,
        rating: rating,
        title: title,
        content: content,
        pros: pros,
        cons: cons,
        status: "published",
        is_verified_purchase: installation.present?
      )

      { success: true, review: review }
    end

    # Categories (cached for 1 hour)
    def list_categories
      return [] unless defined?(PowernodeEnterprise::Engine)

      cache_key = "ai:marketplace:categories"

      Rails.cache.fetch(cache_key, expires_in: CATEGORIES_CACHE_TTL) do
        Ai::MarketplaceCategory.active.root.ordered.includes(:children).to_a
      end
    end

    # Invalidate marketplace caches (call when data changes)
    def self.invalidate_caches
      Rails.cache.delete("ai:marketplace:categories")
      Rails.cache.delete_matched("ai:marketplace:featured:*")
      Rails.cache.delete_matched("ai:marketplace:search:*")
    end

    # Invalidate category cache only
    def self.invalidate_categories_cache
      Rails.cache.delete("ai:marketplace:categories")
    end

    # Invalidate featured templates cache only
    def self.invalidate_featured_cache
      Rails.cache.delete_matched("ai:marketplace:featured:*")
    end

    # Analytics (cached for 1 hour)
    PUBLISHER_ANALYTICS_CACHE_TTL = 1.hour

    def publisher_analytics(publisher, start_date: 30.days.ago, end_date: Time.current)
      return {} unless defined?(PowernodeEnterprise::Engine)

      # Cache key includes date range for different queries
      cache_key = "ai:marketplace:publisher_analytics:#{publisher.id}:#{start_date.to_i}:#{end_date.to_i}"

      Rails.cache.fetch(cache_key, expires_in: PUBLISHER_ANALYTICS_CACHE_TTL) do
        transactions = publisher.marketplace_transactions.completed.for_period(start_date, end_date)

        {
          total_revenue: transactions.sum(:gross_amount_usd),
          total_earnings: transactions.sum(:publisher_amount_usd),
          transaction_count: transactions.count,
          installations: publisher.agent_templates.sum(:installation_count),
          active_installations: publisher.agent_templates.sum(:active_installations),
          average_rating: publisher.average_rating,
          templates_count: publisher.total_templates
        }
      end
    end

    # Invalidate publisher analytics cache
    def self.invalidate_publisher_analytics(publisher_id)
      Rails.cache.delete_matched("ai:marketplace:publisher_analytics:#{publisher_id}:*")
    end

    # Agent Composition — create a team from marketplace templates
    def compose_team(template_ids:, team_name:, team_type: "hierarchical", coordination_strategy: "manager_led", user:)
      templates = Ai::AgentTemplate.published.where(id: template_ids)
      return { success: false, error: "No valid published templates found" } if templates.empty?

      missing = template_ids - templates.map(&:id)
      return { success: false, error: "Templates not found: #{missing.join(', ')}" } if missing.any?

      team = Ai::AgentTeam.create!(
        account: account,
        name: team_name,
        team_type: team_type,
        coordination_strategy: coordination_strategy,
        status: "active"
      )

      agents = templates.map.with_index do |template, index|
        agent = create_agent_from_template(template, nil, {}, user)
        next nil unless agent

        role = index.zero? ? "lead" : "member"
        Ai::AgentTeamMember.create!(
          ai_agent_team_id: team.id,
          ai_agent_id: agent.id,
          role: role,
          status: "active"
        )

        agent
      end.compact

      { success: true, team: team, agents: agents }
    rescue ActiveRecord::RecordInvalid => e
      { success: false, error: e.message }
    end

    # Core usage analytics (non-enterprise) — stats about installed templates
    def installation_analytics
      installations = account.ai_agent_installations.includes(:agent_template)

      active = installations.where(status: "active")
      templates = active.map(&:agent_template).compact

      {
        total_installed: installations.count,
        active_installed: active.count,
        total_executions: active.sum(:executions_count),
        total_cost_usd: active.sum(:total_cost_usd).to_f.round(2),
        by_category: templates.group_by(&:category).transform_values(&:count),
        most_used: active.order(executions_count: :desc).limit(5).map { |i|
          {
            template_name: i.agent_template&.name,
            executions: i.executions_count,
            last_used_at: i.last_used_at
          }
        },
        recently_installed: active.order(created_at: :desc).limit(5).map { |i|
          {
            template_name: i.agent_template&.name,
            installed_at: i.created_at
          }
        }
      }
    end

    private

    def process_template_payment(template)
      return { success: false, error: "Enterprise feature required" } unless defined?(PowernodeEnterprise::Engine)

      # Create transaction record
      publisher = template.publisher
      commission_percentage = 100 - publisher.revenue_share_percentage
      gross_amount = template.price_usd || template.monthly_price_usd

      transaction = Ai::MarketplaceTransaction.create!(
        account: account,
        publisher: publisher,
        agent_template: template,
        transaction_type: template.monthly_price_usd.present? ? "subscription" : "purchase",
        status: "pending",
        gross_amount_usd: gross_amount,
        commission_percentage: commission_percentage
      )

      # In a real implementation, integrate with payment processor
      transaction.complete!

      { success: true, transaction: transaction }
    end

    def create_agent_from_template(template, installation, custom_config, user = nil)
      config = template.agent_config.merge(custom_config)

      # Find a provider for the agent - use account's first active provider or any active provider
      provider = account.ai_providers.where(is_active: true).first ||
                 Ai::Provider.where(is_active: true).first

      return nil unless provider

      Ai::Agent.create!(
        account: account,
        provider: provider,
        creator: user || account.users.first,
        name: "#{template.name} (from template)",
        description: template.description,
        agent_type: config["agent_type"] || "assistant",
        system_prompt: config["system_prompt"],
        metadata: config["configuration"] || {},
        status: "active"
      )
    rescue StandardError => e
      Rails.logger.error "Failed to create agent from template: #{e.message}"
      nil
    end
  end
end
