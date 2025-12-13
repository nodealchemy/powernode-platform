# frozen_string_literal: true

module Mcp
  module NodeExecutors
    # KB Article Update node executor - updates knowledge base articles
    class KbArticleUpdate < Base
      protected

      def perform_execution
        log_info "Updating knowledge base article"

        # Get article identifier
        article_id = configuration["article_id"] || get_variable("article_id")
        article_slug = configuration["article_slug"] || get_variable("article_slug")

        unless article_id.present? || article_slug.present?
          raise Mcp::AiWorkflowOrchestrator::NodeExecutionError,
                "Either article_id or article_slug must be provided"
        end

        # Find the article
        article = find_article(article_id, article_slug)

        # Extract update data
        update_data = extract_update_data

        # Update the article
        update_article(article, update_data)

        # Store updated article data in variable if configured
        if configuration["output_variable"]
          set_variable(configuration["output_variable"], serialize_article(article))
        end

        log_info "Updated KB article: #{article.title} (#{article.id})"

        # Industry-standard output format (v1.0)
        # See: docs/platform/WORKFLOW_IO_STANDARD.md
        {
          output: "Knowledge base article '#{article.title}' updated successfully",
          result: {
            article_id: article.id,
            slug: article.slug,
            status: article.status,
            updated_fields: update_data.keys
          },
          data: {
            article: serialize_article(article)
          },
          metadata: {
            node_id: @node.node_id,
            node_type: "kb_article_update",
            executed_at: Time.current.iso8601,
            operation: "update",
            record_type: "KnowledgeBaseArticle"
          }
        }
      end

      private

      def find_article(article_id, article_slug)
        article = if article_id.present?
                   KnowledgeBaseArticle.find_by(id: article_id)
        else
                   KnowledgeBaseArticle.find_by(slug: article_slug)
        end

        unless article
          identifier = article_id || article_slug
          raise Mcp::AiWorkflowOrchestrator::NodeExecutionError,
                "KB article not found: #{identifier}"
        end

        article
      end

      def extract_update_data
        data = {}

        # Only include fields that are explicitly configured or provided
        data[:title] = configuration["title"] || get_variable("title") if configuration["title"] || configuration["update_title"]
        data[:content] = configuration["content"] || get_variable("content") if configuration["content"] || configuration["update_content"]
        data[:excerpt] = configuration["excerpt"] || get_variable("excerpt") if configuration["excerpt"] || configuration["update_excerpt"]
        data[:status] = configuration["status"] || get_variable("status") if configuration["status"] || configuration["update_status"]
        data[:category_id] = configuration["category_id"] || get_variable("category_id") if configuration["category_id"] || configuration["update_category"]
        data[:is_public] = configuration["is_public"] if configuration.key?("is_public") || configuration["update_is_public"]
        data[:is_featured] = configuration["is_featured"] if configuration.key?("is_featured") || configuration["update_is_featured"]

        # Handle tags update
        tags = configuration["tags"] || get_variable("tags")
        data[:tag_names] = normalize_tags(tags) if tags.present? || configuration["update_tags"]

        # Apply template rendering
        if data[:content].present? && data[:content].include?("{{")
          data[:content] = render_template(data[:content])
        end

        if data[:title].present? && data[:title].include?("{{")
          data[:title] = render_template(data[:title])
        end

        data
      end

      def update_article(article, data)
        # Validate status if being updated
        if data[:status].present?
          valid_statuses = %w[draft review published archived]
          unless valid_statuses.include?(data[:status])
            raise Mcp::AiWorkflowOrchestrator::NodeExecutionError,
                  "Invalid status '#{data[:status]}'. Must be one of: #{valid_statuses.join(', ')}"
          end
        end

        # Validate category if being updated
        if data[:category_id].present? && !KnowledgeBaseCategory.exists?(data[:category_id])
          raise Mcp::AiWorkflowOrchestrator::NodeExecutionError,
                "Category not found: #{data[:category_id]}"
        end

        # Extract tags separately
        tags = data.delete(:tag_names)

        # Update article attributes
        article.update!(data) if data.present?

        # Update tags if provided
        if tags.present?
          article.tag_names = tags
          article.save!
        end

      rescue ActiveRecord::RecordInvalid => e
        raise Mcp::AiWorkflowOrchestrator::NodeExecutionError,
              "Failed to update KB article: #{e.message}"
      end

      def serialize_article(article)
        {
          id: article.id,
          title: article.title,
          slug: article.slug,
          content: article.content,
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
          created_at: article.created_at.iso8601,
          updated_at: article.updated_at.iso8601
        }
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

      def render_template(template)
        return template unless template.is_a?(String)

        result = template.dup

        # Find all {{variable}} patterns and replace with values from execution context
        result.gsub(/\{\{(\w+)\}\}/) do |match|
          variable_name = $1
          value = get_variable(variable_name)
          value.present? ? value.to_s : match
        end
      end
    end
  end
end
