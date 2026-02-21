# frozen_string_literal: true

module Ai
  module Tools
    class PageManagementTool < BaseTool
      REQUIRED_PERMISSION = "pages.manage"

      def self.definition
        {
          name: "page_management",
          description: "List, get, create, or update content Pages",
          parameters: {
            action: { type: "string", required: true, description: "Action: list_pages, get_page, create_page, update_page" },
            page_id: { type: "string", required: false, description: "Page ID (for get/update)" },
            slug: { type: "string", required: false, description: "Page slug (alternative to ID for get)" },
            status: { type: "string", required: false, description: "Filter by status or set status (draft/published)" },
            title: { type: "string", required: false, description: "Page title (for create/update)" },
            content: { type: "string", required: false, description: "Page content in markdown (for create/update)" },
            meta_description: { type: "string", required: false, description: "SEO meta description (for create/update)" },
            meta_keywords: { type: "string", required: false, description: "SEO meta keywords comma-separated (for create/update)" }
          }
        }
      end

      def self.action_definitions
        {
          "list_pages" => {
            description: "List content pages with optional status filter",
            parameters: {
              status: { type: "string", required: false, description: "Filter by status (draft/published)" }
            }
          },
          "get_page" => {
            description: "Get a content page by ID or slug",
            parameters: {
              page_id: { type: "string", required: false, description: "Page ID" },
              slug: { type: "string", required: false, description: "Page slug (alternative to ID)" }
            }
          },
          "create_page" => {
            description: "Create a new content page",
            parameters: {
              title: { type: "string", required: true, description: "Page title" },
              content: { type: "string", required: true, description: "Page content in markdown" },
              slug: { type: "string", required: false, description: "Page slug (auto-generated if omitted)" },
              status: { type: "string", required: false, description: "Status (default: draft)" },
              meta_description: { type: "string", required: false, description: "SEO meta description" },
              meta_keywords: { type: "string", required: false, description: "SEO meta keywords comma-separated" }
            }
          },
          "update_page" => {
            description: "Update an existing content page",
            parameters: {
              page_id: { type: "string", required: true, description: "Page ID" },
              title: { type: "string", required: false, description: "New page title" },
              content: { type: "string", required: false, description: "New page content" },
              slug: { type: "string", required: false, description: "New slug" },
              status: { type: "string", required: false, description: "New status" },
              meta_description: { type: "string", required: false, description: "SEO meta description" },
              meta_keywords: { type: "string", required: false, description: "SEO meta keywords" }
            }
          }
        }
      end

      protected

      def call(params)
        case params[:action]
        when "list_pages" then list_pages(params)
        when "get_page" then get_page(params)
        when "create_page" then create_page(params)
        when "update_page" then update_page(params)
        else { success: false, error: "Unknown action: #{params[:action]}" }
        end
      end

      private

      def list_pages(params)
        scope = Page.all
        scope = scope.where(status: params[:status]) if params[:status].present?
        pages = scope.order(updated_at: :desc).limit(50)
        {
          success: true,
          pages: pages.map { |p| serialize_page_summary(p) }
        }
      end

      def get_page(params)
        page = find_page(params)
        return { success: false, error: "Page not found" } unless page

        { success: true, page: serialize_page_full(page) }
      end

      def create_page(params)
        page = Page.create!(
          title: params[:title],
          content: params[:content],
          status: params[:status] || "draft",
          slug: params[:slug].presence || PageService.generate_slug(params[:title]),
          meta_description: params[:meta_description],
          meta_keywords: params[:meta_keywords]
        )
        { success: true, page_id: page.id, slug: page.slug, title: page.title }
      rescue ActiveRecord::RecordInvalid => e
        { success: false, error: e.message }
      end

      def update_page(params)
        page = find_page(params)
        return { success: false, error: "Page not found" } unless page

        attrs = {}
        attrs[:title] = params[:title] if params[:title].present?
        attrs[:content] = params[:content] if params[:content].present?
        attrs[:slug] = params[:slug] if params[:slug].present?
        attrs[:status] = params[:status] if params[:status].present?
        attrs[:meta_description] = params[:meta_description] if params.key?(:meta_description)
        attrs[:meta_keywords] = params[:meta_keywords] if params.key?(:meta_keywords)

        page.update!(attrs)
        { success: true, page_id: page.id, slug: page.slug }
      rescue ActiveRecord::RecordInvalid => e
        { success: false, error: e.message }
      end

      def find_page(params)
        if params[:page_id].present?
          Page.find_by(id: params[:page_id])
        elsif params[:slug].present?
          Page.find_by(slug: params[:slug])
        end
      end

      def serialize_page_summary(page)
        {
          id: page.id,
          title: page.title,
          slug: page.slug,
          status: page.status,
          updated_at: page.updated_at&.iso8601
        }
      end

      def serialize_page_full(page)
        {
          id: page.id,
          title: page.title,
          slug: page.slug,
          status: page.status,
          content: page.content,
          meta_description: page.meta_description,
          meta_keywords: page.meta_keywords,
          word_count: page.word_count,
          published_at: page.published_at&.iso8601,
          created_at: page.created_at&.iso8601,
          updated_at: page.updated_at&.iso8601
        }
      end
    end
  end
end
