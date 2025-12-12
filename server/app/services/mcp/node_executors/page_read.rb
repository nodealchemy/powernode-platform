# frozen_string_literal: true

module Mcp
  module NodeExecutors
    # Page Read node executor - reads content pages
    class PageRead < Base
      protected

      def perform_execution
        log_info "Reading content page"

        # Get page identifier (ID or slug)
        page_id = configuration["page_id"] || get_variable("page_id")
        page_slug = configuration["page_slug"] || get_variable("page_slug")

        unless page_id.present? || page_slug.present?
          raise Mcp::AiWorkflowOrchestrator::NodeExecutionError,
                "Either page_id or page_slug must be provided"
        end

        # Find the page
        page = find_page(page_id, page_slug)

        # Store page data in variables if configured
        if configuration["output_variable"]
          set_variable(configuration["output_variable"], serialize_page(page))
        end

        log_info "Read page: #{page.title} (#{page.id})"

        # Industry-standard output format (v1.0)
        # See: docs/platform/WORKFLOW_IO_STANDARD.md
        {
          output: page.content,
          result: {
            page_id: page.id,
            title: page.title,
            slug: page.slug,
            status: page.status,
            published: page.published?,
            word_count: page.word_count,
            read_time: page.estimated_read_time
          },
          data: {
            page: serialize_page(page)
          },
          metadata: {
            node_id: @node.node_id,
            node_type: "page_read",
            executed_at: Time.current.iso8601,
            operation: "read",
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
    end
  end
end
