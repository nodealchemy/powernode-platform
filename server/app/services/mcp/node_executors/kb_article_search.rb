# frozen_string_literal: true

module Mcp
  module NodeExecutors
    # KB Article Search node executor - searches knowledge base articles
    class KbArticleSearch < Base
      protected

      def perform_execution
        log_info "Searching knowledge base articles"

        # Get search parameters
        search_params = extract_search_params

        # Perform search
        results = perform_search(search_params)

        # Store results in variable if configured
        if configuration["output_variable"]
          set_variable(configuration["output_variable"], serialize_results(results))
        end

        log_info "Found #{results.count} KB articles matching search criteria"

        # Industry-standard output format (v1.0)
        # See: docs/platform/WORKFLOW_IO_STANDARD.md
        {
          output: "Found #{results.count} articles",
          result: {
            count: results.count,
            has_results: results.any?,
            search_criteria: search_params
          },
          data: {
            articles: serialize_results(results),
            total_count: results.count
          },
          metadata: {
            node_id: @node.node_id,
            node_type: "kb_article_search",
            executed_at: Time.current.iso8601,
            operation: "search",
            record_type: "KnowledgeBase::Article"
          }
        }
      end

      private

      def extract_search_params
        params = {}

        # Text search query
        params[:query] = configuration["query"] || get_variable("query")

        # Filters
        params[:category_id] = configuration["category_id"] || get_variable("category_id")
        params[:status] = configuration["status"] || get_variable("status")
        params[:author_id] = configuration["author_id"] || get_variable("author_id")
        params[:is_public] = configuration["is_public"] if configuration.key?("is_public")
        params[:is_featured] = configuration["is_featured"] if configuration.key?("is_featured")
        params[:tags] = normalize_tags(configuration["tags"] || get_variable("tags"))

        # Pagination
        params[:limit] = (configuration["limit"] || get_variable("limit") || 10).to_i
        params[:offset] = (configuration["offset"] || get_variable("offset") || 0).to_i

        # Sorting
        params[:sort_by] = configuration["sort_by"] || get_variable("sort_by") || "recent"

        params
      end

      def perform_search(params)
        # Start with base query
        query = KnowledgeBase::Article.all

        # Apply text search if query provided
        if params[:query].present?
          query = query.search_by_text(params[:query])
        end

        # Apply filters
        query = query.in_category(params[:category_id]) if params[:category_id].present?
        query = query.where(status: params[:status]) if params[:status].present?
        query = query.by_author(params[:author_id]) if params[:author_id].present?
        query = query.where(is_public: params[:is_public]) unless params[:is_public].nil?
        query = query.where(is_featured: params[:is_featured]) unless params[:is_featured].nil?

        # Apply tag filter
        if params[:tags].present?
          tag_ids = KnowledgeBase::Tag.where(name: params[:tags]).pluck(:id)
          query = query.joins(:article_tags).where(knowledge_base_article_tags: { tag_id: tag_ids })
        end

        # Apply sorting
        query = case params[:sort_by]
        when "recent"
                  query.recent
        when "popular"
                  query.popular
        when "title"
                  query.order(:title)
        else
                  query.ordered
        end

        # Apply pagination
        query = query.limit(params[:limit]).offset(params[:offset])

        query.to_a
      end

      def serialize_results(articles)
        articles.map do |article|
          {
            id: article.id,
            title: article.title,
            slug: article.slug,
            excerpt: article.excerpt,
            status: article.status,
            category_id: article.category_id,
            category_name: article.category.name,
            author_id: article.author_id,
            author_name: article.author.name,
            tags: article.tag_names,
            is_public: article.is_public,
            is_featured: article.is_featured,
            views_count: article.views_count,
            likes_count: article.likes_count,
            reading_time: article.reading_time,
            published_at: article.published_at&.iso8601,
            created_at: article.created_at.iso8601
          }
        end
      end

      def normalize_tags(tags)
        return [] if tags.blank?

        if tags.is_a?(Array)
          tags.map(&:to_s).map(&:strip).reject(&:blank?)
        elsif tags.is_a?(String)
          tags.split(",").map(&:strip).reject(&:blank?)
        else
          []
        end
      end
    end
  end
end
