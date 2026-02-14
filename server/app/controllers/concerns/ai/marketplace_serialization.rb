# frozen_string_literal: true

module Ai
  module MarketplaceSerialization
    extend ActiveSupport::Concern

    private

    def template_json(template, detailed: false)
      json = {
        id: template.id,
        name: template.name,
        slug: template.slug,
        description: template.description,
        category: template.category,
        vertical: template.vertical,
        pricing_type: template.pricing_type,
        price_usd: template.price_usd,
        monthly_price_usd: template.monthly_price_usd,
        version: template.version,
        installation_count: template.installation_count,
        average_rating: template.average_rating,
        review_count: template.review_count,
        is_featured: template.is_featured,
        is_verified: template.is_verified,
        publisher: {
          id: template.publisher.id,
          name: template.publisher.publisher_name,
          slug: template.publisher.publisher_slug,
          verified: template.publisher.verified?
        },
        published_at: template.published_at
      }

      if detailed
        json.merge!(
          long_description: template.long_description,
          agent_config: template.agent_config,
          required_credentials: template.required_credentials,
          required_tools: template.required_tools,
          sample_prompts: template.sample_prompts,
          screenshots: template.screenshots,
          tags: template.tags,
          features: template.features,
          limitations: template.limitations,
          setup_instructions: template.setup_instructions,
          changelog: template.changelog
        )
      end

      json
    end

    def installation_json(installation)
      {
        id: installation.id,
        status: installation.status,
        installed_version: installation.installed_version,
        license_type: installation.license_type,
        executions_count: installation.executions_count,
        total_cost_usd: installation.total_cost_usd,
        last_used_at: installation.last_used_at,
        created_at: installation.created_at,
        template: {
          id: installation.agent_template.id,
          name: installation.agent_template.name,
          slug: installation.agent_template.slug
        }
      }
    end

    def review_json(review)
      {
        id: review.id,
        rating: review.rating,
        title: review.title,
        content: review.content,
        pros: review.pros,
        cons: review.cons,
        is_verified_purchase: review.is_verified_purchase,
        helpful_count: review.helpful_count,
        created_at: review.created_at
      }
    end

    def category_json(category)
      {
        id: category.id,
        name: category.name,
        slug: category.slug,
        description: category.description,
        icon: category.icon,
        template_count: category.template_count,
        children: category.children.active.ordered.map { |c| category_json(c) }
      }
    end

    def publisher_json(publisher)
      {
        id: publisher.id,
        name: publisher.publisher_name,
        slug: publisher.publisher_slug,
        description: publisher.description,
        website_url: publisher.website_url,
        status: publisher.status,
        verification_status: publisher.verification_status,
        total_templates: publisher.total_templates,
        total_installations: publisher.total_installations,
        average_rating: publisher.average_rating,
        lifetime_earnings_usd: publisher.lifetime_earnings_usd,
        pending_payout_usd: publisher.pending_payout_usd
      }
    end

    def pagination_meta(collection)
      {
        current_page: collection.current_page,
        total_pages: collection.total_pages,
        total_count: collection.total_count,
        per_page: collection.limit_value
      }
    end
  end
end
