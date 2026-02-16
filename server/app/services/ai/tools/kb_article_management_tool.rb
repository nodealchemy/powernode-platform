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
        scope = ::KnowledgeBase::Article.all
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

        author = ::User.find_by(email: "admin@powernode.org") || ::User.first
        article = ::KnowledgeBase::Article.create!(
          title: params[:title],
          content: params[:content],
          category: category,
          author: author,
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

        article.update!(attrs)
        article.tag_names = Array(params[:tags]) if params[:tags].present?

        { success: true, article_id: article.id, slug: article.slug }
      rescue ActiveRecord::RecordInvalid => e
        { success: false, error: e.message }
      end

      def find_article(params)
        if params[:article_id].present?
          ::KnowledgeBase::Article.find_by(id: params[:article_id])
        elsif params[:slug].present?
          ::KnowledgeBase::Article.find_by(slug: params[:slug])
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
