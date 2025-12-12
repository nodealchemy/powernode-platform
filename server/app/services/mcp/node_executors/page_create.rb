# frozen_string_literal: true

module Mcp
  module NodeExecutors
    # Page Create node executor - creates content pages
    class PageCreate < Base
      protected

      def perform_execution
        log_info "Creating content page"

        # Extract page data from configuration and input
        page_data = extract_page_data

        # Validate required fields
        validate_page_data!(page_data)

        # Create the page
        page = create_page(page_data)

        # Store page ID in variable if configured
        if configuration["output_variable"]
          set_variable(configuration["output_variable"], page.id)
        end

        log_info "Created page: #{page.title} (#{page.id})"

        # Industry-standard output format (v1.0)
        # See: docs/platform/WORKFLOW_IO_STANDARD.md
        {
          output: "Page '#{page.title}' created successfully",
          result: {
            page_id: page.id,
            slug: page.slug,
            status: page.status,
            published: page.published?
          },
          data: {
            page: {
              id: page.id,
              title: page.title,
              slug: page.slug,
              content: page.content,
              status: page.status,
              meta_description: page.meta_description,
              meta_keywords: page.meta_keywords,
              created_at: page.created_at.iso8601,
              updated_at: page.updated_at.iso8601
            }
          },
          metadata: {
            node_id: @node.node_id,
            node_type: "page_create",
            executed_at: Time.current.iso8601,
            operation: "create",
            record_type: "Page"
          }
        }
      end

      private

      def extract_page_data
        data = {}

        # Get data from configuration or variables
        data[:title] = configuration["title"] || get_variable("title")
        data[:content] = configuration["content"] || get_variable("content")
        data[:slug] = configuration["slug"] || get_variable("slug")
        data[:status] = configuration["status"] || get_variable("status") || "draft"
        data[:meta_description] = configuration["meta_description"] || get_variable("meta_description")
        data[:meta_keywords] = configuration["meta_keywords"] || get_variable("meta_keywords")

        # Apply template rendering to content if needed
        if data[:content].present? && data[:content].include?("{{")
          data[:content] = render_template(data[:content])
        end

        # Apply template rendering to title if needed
        if data[:title].present? && data[:title].include?("{{")
          data[:title] = render_template(data[:title])
        end

        data
      end

      def validate_page_data!(data)
        errors = []
        errors << "Title is required" if data[:title].blank?
        errors << "Content is required" if data[:content].blank?

        unless errors.empty?
          raise Mcp::AiWorkflowOrchestrator::NodeExecutionError,
                "Page validation failed: #{errors.join(', ')}"
        end

        # Validate status
        valid_statuses = %w[draft published]
        unless valid_statuses.include?(data[:status])
          raise Mcp::AiWorkflowOrchestrator::NodeExecutionError,
                "Invalid status '#{data[:status]}'. Must be one of: #{valid_statuses.join(', ')}"
        end
      end

      def create_page(data)
        # Get author from workflow context
        author = @orchestrator.user || User.find_by(email: "system@powernode.ai")

        # Create the page
        page = Page.create!(
          title: data[:title],
          content: data[:content],
          slug: data[:slug], # Will be auto-generated if nil
          status: data[:status],
          author_id: author.id,
          meta_description: data[:meta_description],
          meta_keywords: data[:meta_keywords]
        )

        page
      rescue ActiveRecord::RecordInvalid => e
        raise Mcp::AiWorkflowOrchestrator::NodeExecutionError,
              "Failed to create page: #{e.message}"
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
