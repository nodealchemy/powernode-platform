# frozen_string_literal: true

module Mcp
  module NodeExecutors
    # KB Article Publish node executor - publishes knowledge base articles
    class KbArticlePublish < Base
      protected

      def perform_execution
        log_info "Publishing knowledge base article"

        # Get article identifier
        article_id = configuration['article_id'] || get_variable('article_id')
        article_slug = configuration['article_slug'] || get_variable('article_slug')

        unless article_id.present? || article_slug.present?
          raise Mcp::AiWorkflowOrchestrator::NodeExecutionError,
                "Either article_id or article_slug must be provided"
        end

        # Find the article
        article = find_article(article_id, article_slug)

        # Get publish options
        make_public = configuration['make_public'] || get_variable('make_public') || false
        make_featured = configuration['make_featured'] || get_variable('make_featured') || false

        # Publish the article
        publish_article(article, make_public, make_featured)

        # Store published article data in variable if configured
        if configuration['output_variable']
          set_variable(configuration['output_variable'], serialize_article(article))
        end

        log_info "Published KB article: #{article.title} (#{article.id})"

        # Industry-standard output format (v1.0)
        # See: docs/platform/WORKFLOW_IO_STANDARD.md
        {
          output: "Knowledge base article '#{article.title}' published successfully",
          result: {
            article_id: article.id,
            slug: article.slug,
            status: article.status,
            is_public: article.is_public,
            is_featured: article.is_featured,
            published_at: article.published_at&.iso8601
          },
          data: {
            article: serialize_article(article)
          },
          metadata: {
            node_id: @node.node_id,
            node_type: 'kb_article_publish',
            executed_at: Time.current.iso8601,
            operation: 'publish',
            record_type: 'KnowledgeBaseArticle'
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

      def publish_article(article, make_public, make_featured)
        # Validate article is ready to publish
        validate_article_for_publishing!(article)

        # Update article status and settings
        article.update!(
          status: 'published',
          published_at: Time.current,
          is_public: make_public,
          is_featured: make_featured
        )

      rescue ActiveRecord::RecordInvalid => e
        raise Mcp::AiWorkflowOrchestrator::NodeExecutionError,
              "Failed to publish KB article: #{e.message}"
      end

      def validate_article_for_publishing!(article)
        errors = []

        # Check required fields
        errors << "Article must have a title" if article.title.blank?
        errors << "Article must have content" if article.content.blank?
        errors << "Article must have a category" if article.category_id.blank?

        # Check if already published
        if article.status == 'published'
          log_debug "Article is already published, updating publish settings"
        end

        unless errors.empty?
          raise Mcp::AiWorkflowOrchestrator::NodeExecutionError,
                "Article validation failed: #{errors.join(', ')}"
        end
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
    end
  end
end
