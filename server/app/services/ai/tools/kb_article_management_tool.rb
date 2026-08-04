# frozen_string_literal: true

module Ai
  module Tools
    class KbArticleManagementTool < BaseTool
      REQUIRED_PERMISSION = "kb.manage"

      def self.definition
        {
          name: "kb_article_management",
          description: "List, get, create, or update Knowledge Base articles",
          parameters: {
            action: { type: "string", required: true, description: "Action: list_kb_articles, get_kb_article, create_kb_article, update_kb_article" },
            article_id: { type: "string", required: false, description: "Article ID (for get/update)" },
            slug: { type: "string", required: false, description: "Article slug (alternative to ID for get)" },
            category_slug: { type: "string", required: false, description: "Category slug (for list/create)" },
            status: { type: "string", required: false, description: "Filter by status or set status (draft/review/published/archived)" },
            title: { type: "string", required: false, description: "Article title (for create/update)" },
            content: { type: "string", required: false, description: "Article content in markdown (for create/update)" },
            excerpt: { type: "string", required: false, description: "Article excerpt (for create/update)" },
            is_featured: { type: "boolean", required: false, description: "Featured flag (for create/update)" },
            tags: { type: "array", required: false, description: "Tag names (for create/update)" }
          }
        }
      end

      def self.action_definitions
        {
          "list_kb_articles" => {
            description: "List Knowledge Base articles with optional category and status filters",
            parameters: {
              category_slug: { type: "string", required: false, description: "Filter by category slug" },
              status: { type: "string", required: false, description: "Filter by status (draft/review/published/archived)" }
            }
          },
          "get_kb_article" => {
            description: "Get a Knowledge Base article by ID or slug",
            parameters: {
              article_id: { type: "string", required: false, description: "Article ID" },
              slug: { type: "string", required: false, description: "Article slug (alternative to ID)" }
            }
          },
          "create_kb_article" => {
            description: "Create a new Knowledge Base article in a category",
            parameters: {
              title: { type: "string", required: true, description: "Article title" },
              content: { type: "string", required: true, description: "Article content in markdown" },
              category_slug: { type: "string", required: true, description: "Category slug" },
              status: { type: "string", required: false, description: "Status (default: draft)" },
              excerpt: { type: "string", required: false, description: "Article excerpt" },
              is_featured: { type: "boolean", required: false, description: "Featured flag" },
              tags: { type: "array", required: false, description: "Tag names" }
            }
          },
          "update_kb_article" => {
            description: "Update an existing Knowledge Base article",
            parameters: {
              article_id: { type: "string", required: true, description: "Article ID" },
              title: { type: "string", required: false, description: "New article title" },
              content: { type: "string", required: false, description: "New article content" },
              excerpt: { type: "string", required: false, description: "New article excerpt" },
              status: { type: "string", required: false, description: "New status" },
              is_featured: { type: "boolean", required: false, description: "Featured flag" },
              tags: { type: "array", required: false, description: "Tag names" }
            }
          }
        }
      end

      protected

      def call(params)
        case params[:action]
        when "list_kb_articles" then list_articles(params)
        when "get_kb_article" then get_article(params)
        when "create_kb_article" then create_article(params)
        when "update_kb_article" then update_article(params)
        else { success: false, error: "Unknown action: #{params[:action]}" }
        end
      end

      private

      def list_articles(params)
        # Override-aware: GLOBAL (platform-provided) articles plus the account's
        # own — never another tenant's private articles.
        scope = ::KnowledgeBase::Article.for_account(account.id)
        scope = scope.where(category: find_category(params[:category_slug])) if params[:category_slug].present?
        scope = scope.where(status: params[:status]) if params[:status].present?
        articles = scope.order(updated_at: :desc).limit(50)
        {
          success: true,
          articles: articles.map { |a| serialize_article_summary(a) }
        }
      end

      def get_article(params)
        article = find_article(params)
        return { success: false, error: "Article not found" } unless article

        { success: true, article: serialize_article_full(article) }
      end

      def create_article(params)
        category = find_category(params[:category_slug])
        return { success: false, error: "Category not found: #{params[:category_slug]}" } unless category

        article = nil

        ActiveRecord::Base.transaction do
          article = ::KnowledgeBase::Article.create!(
            title: params[:title],
            content: params[:content],
            category: category,
            author: default_author,
            status: params[:status] || "draft",
            excerpt: params[:excerpt],
            is_featured: params[:is_featured] || false,
            is_public: true,
            views_count: 0,
            likes_count: 0,
            sort_order: 0
          )

          if params[:tags].present?
            article.tag_names = Array(params[:tags])
          end

          # A create that lands straight in `published` stays a `create` row —
          # one event happened, not two. "Who published this" is answered across
          # both shapes by the to_status index, not by the action.
          record_article_workflow!(
            article,
            action: "create",
            from_status: nil,
            to_status: article.status
          )
        end

        { success: true, article_id: article.id, slug: article.slug, title: article.title }
      rescue ActiveRecord::RecordInvalid => e
        { success: false, error: e.message }
      end

      def update_article(params)
        article = find_article(params)
        return { success: false, error: "Article not found" } unless article

        attrs = {}
        attrs[:title] = params[:title] if params[:title].present?
        attrs[:content] = params[:content] if params[:content].present?
        attrs[:excerpt] = params[:excerpt] if params[:excerpt].present?
        attrs[:status] = params[:status] if params[:status].present?
        attrs[:is_featured] = params[:is_featured] unless params[:is_featured].nil?

        from_status = article.status

        ActiveRecord::Base.transaction do
          article.update!(attrs)

          # Read the summary before tag assignment resets saved_changes.
          summary = ::KnowledgeBase::Workflow.change_summary(article)
          article.tag_names = Array(params[:tags]) if params[:tags].present?

          record_article_workflow!(
            article,
            action: ::KnowledgeBase::Workflow.action_for(from_status, article.status),
            from_status: from_status,
            to_status: article.status,
            comment: summary
          )
        end

        { success: true, article_id: article.id, slug: article.slug }
      rescue ActiveRecord::RecordInvalid => e
        { success: false, error: e.message }
      end

      # Records an article state transition, blocking like the controller does:
      # a bare create! inside the caller's transaction, so a transition that
      # cannot be recorded is rolled back. The surrounding
      # `rescue ActiveRecord::RecordInvalid` then reports it to the agent as a
      # failed call rather than a silent partial success.
      def record_article_workflow!(article, action:, from_status:, to_status:, comment: nil, metadata: {})
        principal, attribution = workflow_principal(article)

        ::KnowledgeBase::Workflow.create!(
          article: article,
          user: principal,
          action: action,
          from_status: from_status,
          to_status: to_status,
          comment: comment,
          metadata: metadata.merge(
            source: "ai_tool",
            tool: self.class.tool_name,
            agent_id: agent&.id,
            agent_name: agent&.name,
            attribution: attribution
          ).compact
        )
      end

      # knowledge_base_workflows.user_id is NOT NULL, so every row needs a
      # principal — but an agent-driven call frequently has no acting user
      # (BaseTool#user is nil for both agent and instance principals) and the
      # seeded GLOBAL articles are deliberately authorless (db/seeds/kb/*.rb set
      # author_id = nil on 53 of them). The chain therefore falls back to the
      # same admin this tool already picks as an author, and returns which link
      # was used so `metadata.attribution` records it: the row never claims a
      # fallback user performed the action, and `metadata.agent_id` carries the
      # actor the column cannot express.
      def workflow_principal(article)
        return [ user, "acting_user" ] if user
        return [ article.author, "article_author" ] if article.author

        [ default_author, "fallback_admin" ]
      end

      def default_author
        ::User.find_by(email: "admin@powernode.org") || ::User.first
      end

      def find_article(params)
        scope = ::KnowledgeBase::Article.for_account(account.id)
        if params[:article_id].present?
          scope.find_by(id: params[:article_id])
        elsif params[:slug].present?
          scope.find_by(slug: params[:slug])
        end
      end

      def find_category(slug)
        return nil unless slug.present?
        ::KnowledgeBase::Category.find_by(slug: slug)
      end

      def serialize_article_summary(article)
        {
          id: article.id,
          title: article.title,
          slug: article.slug,
          status: article.status,
          category: article.category&.name,
          is_featured: article.is_featured,
          updated_at: article.updated_at&.iso8601
        }
      end

      def serialize_article_full(article)
        {
          id: article.id,
          title: article.title,
          slug: article.slug,
          status: article.status,
          content: article.content,
          excerpt: article.excerpt,
          category: article.category&.name,
          category_slug: article.category&.slug,
          author: article.author&.email,
          is_featured: article.is_featured,
          is_public: article.is_public,
          tags: article.tag_names,
          views_count: article.views_count,
          published_at: article.published_at&.iso8601,
          created_at: article.created_at&.iso8601,
          updated_at: article.updated_at&.iso8601
        }
      end
    end
  end
end
