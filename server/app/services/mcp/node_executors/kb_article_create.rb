# frozen_string_literal: true

module Mcp
  module NodeExecutors
    # KB Article Create node executor - creates knowledge base articles
    class KbArticleCreate < Base
      protected

      def perform_execution
        log_info "Creating knowledge base article"

        # Extract article data from configuration and input
        article_data = extract_article_data

        # Validate required fields
        validate_article_data!(article_data)

        # Create the article
        article = create_article(article_data)

        # Store article ID in variable if configured
        if configuration['output_variable']
          set_variable(configuration['output_variable'], article.id)
        end

        log_info "Created KB article: #{article.title} (#{article.id})"

        # Industry-standard output format (v1.0)
        # See: docs/platform/WORKFLOW_IO_STANDARD.md
        {
          output: "Knowledge base article '#{article.title}' created successfully",
          result: {
            article_id: article.id,
            slug: article.slug,
            status: article.status,
            published: article.published?
          },
          data: {
            article: {
              id: article.id,
              title: article.title,
              slug: article.slug,
              content: article.content,
              excerpt: article.excerpt,
              status: article.status,
              category_id: article.category_id,
              tags: article.tag_names,
              is_public: article.is_public,
              is_featured: article.is_featured,
              created_at: article.created_at.iso8601,
              updated_at: article.updated_at.iso8601
            }
          },
          metadata: {
            node_id: @node.node_id,
            node_type: 'kb_article_create',
            executed_at: Time.current.iso8601,
            operation: 'create',
            record_type: 'KnowledgeBaseArticle'
          }
        }
      end

      private

      def extract_article_data
        data = {}

        # Get data from configuration
        data[:title] = configuration['title'] || get_variable('title')
        data[:content] = configuration['content'] || get_variable('content')
        data[:excerpt] = configuration['excerpt'] || get_variable('excerpt')
        data[:status] = configuration['status'] || get_variable('status') || 'draft'
        data[:category_id] = configuration['category_id'] || get_variable('category_id')
        data[:is_public] = configuration['is_public'] || get_variable('is_public') || false
        data[:is_featured] = configuration['is_featured'] || get_variable('is_featured') || false

        # Handle tags (array or comma-separated string)
        tags = configuration['tags'] || get_variable('tags')
        data[:tag_names] = normalize_tags(tags) if tags.present?

        # Apply template rendering to content if needed
        if data[:content].present? && data[:content].include?('{{')
          data[:content] = render_template(data[:content])
        end

        # Apply template rendering to title if needed
        if data[:title].present? && data[:title].include?('{{')
          data[:title] = render_template(data[:title])
        end

        data
      end

      def validate_article_data!(data)
        errors = []
        errors << "Title is required" if data[:title].blank?
        errors << "Content is required" if data[:content].blank?
        errors << "Category is required" if data[:category_id].blank?

        unless errors.empty?
          raise Mcp::WorkflowOrchestrator::NodeExecutionError,
                "KB Article validation failed: #{errors.join(', ')}"
        end

        # Validate status
        valid_statuses = %w[draft review published archived]
        unless valid_statuses.include?(data[:status])
          raise Mcp::WorkflowOrchestrator::NodeExecutionError,
                "Invalid status '#{data[:status]}'. Must be one of: #{valid_statuses.join(', ')}"
        end

        # Validate category exists
        unless KnowledgeBaseCategory.exists?(data[:category_id])
          raise Mcp::WorkflowOrchestrator::NodeExecutionError,
                "Category not found: #{data[:category_id]}"
        end
      end

      def create_article(data)
        # Get author from workflow context
        author = @orchestrator.user || User.find_by(email: 'system@powernode.ai')

        # Create the article
        article = KnowledgeBaseArticle.create!(
          title: data[:title],
          content: data[:content],
          excerpt: data[:excerpt],
          status: data[:status],
          category_id: data[:category_id],
          author: author,
          is_public: data[:is_public],
          is_featured: data[:is_featured]
        )

        # Assign tags if provided
        if data[:tag_names].present?
          article.tag_names = data[:tag_names]
          article.save!
        end

        article
      rescue ActiveRecord::RecordInvalid => e
        raise Mcp::WorkflowOrchestrator::NodeExecutionError,
              "Failed to create KB article: #{e.message}"
      end

      def normalize_tags(tags)
        return [] if tags.blank?

        if tags.is_a?(Array)
          tags.map(&:to_s).map(&:strip).reject(&:blank?)
        elsif tags.is_a?(String)
          tags.split(',').map(&:strip).reject(&:blank?)
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
