# frozen_string_literal: true

module Mcp
  module NodeExecutors
    # Page Publish node executor - publishes content pages
    class PagePublish < Base
      protected

      def perform_execution
        log_info "Publishing content page"

        # Get page identifier
        page_id = configuration["page_id"] || get_variable("page_id")
        page_slug = configuration["page_slug"] || get_variable("page_slug")

        unless page_id.present? || page_slug.present?
          raise Mcp::AiWorkflowOrchestrator::NodeExecutionError,
                "Either page_id or page_slug must be provided"
        end

        # Find the page
        page = find_page(page_id, page_slug)

        # Publish the page
        publish_page(page)

        # Store published page data in variable if configured
        if configuration["output_variable"]
          set_variable(configuration["output_variable"], serialize_page(page))
        end

        log_info "Published page: #{page.title} (#{page.id})"

        # Industry-standard output format (v1.0)
        # See: docs/platform/WORKFLOW_IO_STANDARD.md
        {
          output: "Page '#{page.title}' published successfully",
          result: {
            page_id: page.id,
            slug: page.slug,
            status: page.status,
            published_at: page.published_at&.iso8601
          },
          data: {
            page: serialize_page(page)
          },
          metadata: {
            node_id: @node.node_id,
            node_type: "page_publish",
            executed_at: Time.current.iso8601,
            operation: "publish",
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

      def publish_page(page)
        # Validate page is ready to publish
        validate_page_for_publishing!(page)

        # Publish the page
        page.publish!

      rescue ActiveRecord::RecordInvalid => e
        raise Mcp::AiWorkflowOrchestrator::NodeExecutionError,
              "Failed to publish page: #{e.message}"
      end

      def validate_page_for_publishing!(page)
        errors = []

        # Check required fields
        errors << "Page must have a title" if page.title.blank?
        errors << "Page must have content" if page.content.blank?

        # Check if already published
        if page.status == "published"
          log_debug "Page is already published, updating publish timestamp"
        end

        unless errors.empty?
          raise Mcp::AiWorkflowOrchestrator::NodeExecutionError,
                "Page validation failed: #{errors.join(', ')}"
        end
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
