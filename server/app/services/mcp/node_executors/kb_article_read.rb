# frozen_string_literal: true

module Mcp
  module NodeExecutors
    # KB Article Read node executor - reads knowledge base articles
    class KbArticleRead < Base
      protected

      def perform_execution
        log_info "Reading knowledge base article"

        # Get article identifier (ID or slug)
        article_id = configuration['article_id'] || get_variable('article_id')
        article_slug = configuration['article_slug'] || get_variable('article_slug')

        unless article_id.present? || article_slug.present?
          raise Mcp::WorkflowOrchestrator::NodeExecutionError,
                "Either article_id or article_slug must be provided"
        end

        # Find the article
        article = find_article(article_id, article_slug)

        # Store article data in variables if configured
        if configuration['output_variable']
          set_variable(configuration['output_variable'], serialize_article(article))
        end

        log_info "Read KB article: #{article.title} (#{article.id})"

        # Industry-standard output format (v1.0)
        # See: docs/platform/WORKFLOW_IO_STANDARD.md
        {
          output: article.content,
          result: {
            article_id: article.id,
            title: article.title,
            slug: article.slug,
            status: article.status,
            published: article.published?,
            views_count: article.views_count,
            reading_time: article.reading_time
          },
          data: {
            article: serialize_article(article)
          },
          metadata: {
            node_id: @node.node_id,
            node_type: 'kb_article_read',
            executed_at: Time.current.iso8601,
            operation: 'read',
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
          raise Mcp::WorkflowOrchestrator::NodeExecutionError,
                "KB article not found: #{identifier}"
        end

        article
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
