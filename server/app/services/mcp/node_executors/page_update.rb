# frozen_string_literal: true

module Mcp
  module NodeExecutors
    # Page Update node executor - updates content pages
    class PageUpdate < Base
      protected

      def perform_execution
        log_info "Updating content page"

        # Get page identifier
        page_id = configuration["page_id"] || get_variable("page_id")
        page_slug = configuration["page_slug"] || get_variable("page_slug")

        unless page_id.present? || page_slug.present?
          raise Mcp::AiWorkflowOrchestrator::NodeExecutionError,
                "Either page_id or page_slug must be provided"
        end

        # Find the page
        page = find_page(page_id, page_slug)

        # Extract update data
        update_data = extract_update_data

        # Update the page
        update_page(page, update_data)

        # Store updated page data in variable if configured
        if configuration["output_variable"]
          set_variable(configuration["output_variable"], serialize_page(page))
        end

        log_info "Updated page: #{page.title} (#{page.id})"

        # Industry-standard output format (v1.0)
        # See: docs/platform/WORKFLOW_IO_STANDARD.md
        {
          output: "Page '#{page.title}' updated successfully",
          result: {
            page_id: page.id,
            slug: page.slug,
            status: page.status,
            updated_fields: update_data.keys
          },
          data: {
            page: serialize_page(page)
          },
          metadata: {
            node_id: @node.node_id,
            node_type: "page_update",
            executed_at: Time.current.iso8601,
            operation: "update",
            record_type: "Page"
          }
        }
      end

      private

      def find_page(page_id, page_slug)
        page = if page_id.present?
                Page.find_by(id: page_id)
        else
                Page.find_by(slug: page_slug)
        end

        unless page
          identifier = page_id || page_slug
          raise Mcp::AiWorkflowOrchestrator::NodeExecutionError,
                "Page not found: #{identifier}"
        end

        page
      end

      def extract_update_data
        data = {}

        # Only include fields that are explicitly configured or provided
        data[:title] = configuration["title"] || get_variable("title") if configuration["title"] || configuration["update_title"]
        data[:content] = configuration["content"] || get_variable("content") if configuration["content"] || configuration["update_content"]
        data[:slug] = configuration["slug"] || get_variable("slug") if configuration["slug"] || configuration["update_slug"]
        data[:status] = configuration["status"] || get_variable("status") if configuration["status"] || configuration["update_status"]
        data[:meta_description] = configuration["meta_description"] || get_variable("meta_description") if configuration["meta_description"] || configuration["update_meta_description"]
        data[:meta_keywords] = configuration["meta_keywords"] || get_variable("meta_keywords") if configuration["meta_keywords"] || configuration["update_meta_keywords"]

        # Apply template rendering
        if data[:content].present? && data[:content].include?("{{")
          data[:content] = render_template(data[:content])
        end

        if data[:title].present? && data[:title].include?("{{")
          data[:title] = render_template(data[:title])
        end

        data
      end

      def update_page(page, data)
        # Validate status if being updated
        if data[:status].present?
          valid_statuses = %w[draft published]
          unless valid_statuses.include?(data[:status])
            raise Mcp::AiWorkflowOrchestrator::NodeExecutionError,
                  "Invalid status '#{data[:status]}'. Must be one of: #{valid_statuses.join(', ')}"
          end
        end

        # Update page attributes
        page.update!(data) if data.present?

      rescue ActiveRecord::RecordInvalid => e
        raise Mcp::AiWorkflowOrchestrator::NodeExecutionError,
              "Failed to update page: #{e.message}"
      end

      def serialize_page(page)
        {
          id: page.id,
          title: page.title,
          slug: page.slug,
          content: page.content,
          status: page.status,
          author_id: page.author_id,
          author_name: page.author.name,
          meta_description: page.meta_description,
          meta_keywords: page.meta_keywords,
          word_count: page.word_count,
          read_time: page.estimated_read_time,
          published_at: page.published_at&.iso8601,
          created_at: page.created_at.iso8601,
          updated_at: page.updated_at.iso8601
        }
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
