# frozen_string_literal: true

module Ai
  module Tools
    class PageManagementTool < BaseTool
      REQUIRED_PERMISSION = "pages.manage"

      # APO-1a (IMP-1e58753b3b6c) — governance declarations for every action
      # this tool advertises. NON-ENFORCING: `mutating:` alone leaves
      # BaseTool#gated_action? false, so #execute still routes to #call and
      # behaviour is unchanged. Gate wiring (categories/executors) is APO-1e.
      declare_action "create_page", mutating: true,
                                    returns: "page_id, slug and title",
                                    refuses: [ "the call carries no account or no acting user",
                                               "title or content is blank, the slug is already taken, or status is not draft or published" ]
      declare_action "get_page", mutating: false,
                                 returns: "the page's content, status, meta fields, word_count and timestamps",
                                 refuses: [ "the call carries no account",
                                            "neither page_id nor slug matches a page in this account" ],
                                 see_also: { "list_pages" => "finding a page's id or slug" }
      declare_action "list_pages", mutating: false, limit: 50, returns: "page summaries, most recently updated first",
                                   refuses: "the call carries no account"
      declare_action "update_page", mutating: true,
                                    returns: "page_id and slug",
                                    refuses: [ "the call carries no account",
                                               "the page is not in this account",
                                               "the new values fail validation, such as a slug already taken or an unknown status" ]

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
            description: "Get a content page by ID or slug. " \
                         "The id is used when both are given.",
            parameters: {
              page_id: { type: "string", required: false, description: "Page ID" },
              slug: { type: "string", required: false, description: "Page slug (alternative to ID)" }
            }
          },
          "create_page" => {
            description: "Create a new content page in this account, authored by the acting user. " \
                         "The status defaults to draft, and the slug is generated from the title when omitted. " \
                         "Refused when the call carries no acting user.",
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
            description: "Update an existing content page. " \
                         "Only the fields you pass are changed; passing meta_description or meta_keywords empty clears it.",
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
        # No account, no tenant to act in. There used to be an Account.first
        # fallback here, which silently read and wrote whichever tenant happened
        # to be first in the table.
        return missing_context_result("account") if @account.nil?

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
        scope = pages_scope
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
        # pages.author_id is NOT NULL. Without an acting user there is nobody
        # to name as author, and the old User.first fallback named a user from
        # an arbitrary account. Refuse instead.
        return missing_context_result("user") if @user.nil?

        page = Page.create!(
          title: params[:title],
          content: params[:content],
          status: params[:status] || "draft",
          slug: params[:slug].presence || PageService.generate_slug(params[:title]),
          meta_description: params[:meta_description],
          meta_keywords: params[:meta_keywords],
          account: @account,
          author_id: @user.id
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
          pages_scope.find_by(id: params[:page_id])
        elsif params[:slug].present?
          pages_scope.find_by(slug: params[:slug])
        end
      end

      # Account-scoped page relation — mirrors create_page's account binding so
      # list/get/update can only ever touch the tool account's pages (no IDOR).
      def pages_scope
        @account.pages
      end

      def missing_context_result(what)
        { success: false, error: "Refused: the call carries no #{what} context" }
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
