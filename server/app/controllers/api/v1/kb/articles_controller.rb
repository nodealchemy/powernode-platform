# frozen_string_literal: true

class Api::V1::Kb::ArticlesController < ApplicationController
  skip_before_action :authenticate_request, only: [ :index, :show, :search ]
  # Try to authenticate if token provided (allows viewing drafts for editors)
  before_action :authenticate_optional, only: [ :index, :show, :search ]
  before_action :set_article, only: [ :show, :update, :destroy, :publish, :unpublish ]
  before_action :authorize_kb_edit, only: [ :create, :update, :destroy, :bulk_update, :bulk_delete ]
  before_action :authorize_kb_publish, only: [ :publish, :unpublish ]
  before_action :authorize_kb_manage, only: [ :analytics ]

  # GET /api/v1/kb/articles
  def index
    if editing_mode?
      # Admin view with all articles for editing
      articles = KnowledgeBaseArticle.includes(:author, :category, :tags)
      articles = apply_admin_filters(articles)
      articles = articles.page(params[:page]).per(params[:per_page] || 20)

      render_success({
        articles: articles.map { |article| serialize_article_admin(article) },
        pagination: pagination_meta(articles),
        stats: calculate_article_stats
      })
    else
      # Public view with only published articles
      articles = KnowledgeBaseArticle.published.public_articles
      articles = apply_filters(articles)
      articles = articles.includes(:author, :category, :tags).page(params[:page]).per(params[:per_page] || 20)

      render_success({
        articles: articles.map { |article| serialize_article_summary(article) },
        pagination: pagination_meta(articles)
      })
    end
  end

  # GET /api/v1/kb/articles/:id
  def show
    return render_error("Article not found", status: :not_found) unless @article

    # Check access permissions
    if editing_mode?
      # Admin view - can see any article if has edit permissions
      return render_error("Access denied", status: :forbidden) unless can_edit_kb?

      render_success({
        article: serialize_article_detailed(@article)
      })
    else
      # Public view - check if article is viewable
      return render_error("Access denied", status: :forbidden) unless @article.viewable_by?(current_user)

      # Record view with tracking (no session in API-only mode)
      @article.record_view!(
        user: current_user,
        session_id: SecureRandom.hex(16), # Generate unique session identifier for tracking
        ip_address: request.remote_ip,
        user_agent: request.user_agent
      )

      render_success({
        article: serialize_article_full(@article),
        related_articles: @article.related_articles.map { |article| serialize_article_summary(article) }
      })
    end
  end

  # POST /api/v1/kb/articles
  def create
    article = KnowledgeBaseArticle.new(article_params)
    article.author = current_user

    if article.save
      handle_tag_assignment(article) if params[:article][:tag_names].present?

      render_success({
        article: serialize_article_admin(article.reload)
      }, "Article created successfully")
    else
      render_validation_error(article)
    end
  end

  # PATCH /api/v1/kb/articles/:id
  def update
    return render_error("Article not found", status: :not_found) unless @article
    return render_error("Access denied", status: :forbidden) unless @article.editable_by?(current_user)

    if @article.update(article_params)
      handle_tag_assignment(@article) if params[:article][:tag_names].present?

      render_success({
        article: serialize_article_admin(@article.reload)
      }, "Article updated successfully")
    else
      render_validation_error(@article)
    end
  end

  # DELETE /api/v1/kb/articles/:id
  def destroy
    return render_error("Article not found", status: :not_found) unless @article
    return render_error("Access denied", status: :forbidden) unless @article.editable_by?(current_user)

    @article.destroy
    render_success(message: "Article deleted successfully")
  end

  # POST /api/v1/kb/articles/:id/publish
  def publish
    return render_error("Article not found", status: :not_found) unless @article

    if @article.update(status: "published", published_at: Time.current)
      render_success({
        article: serialize_article_admin(@article)
      }, "Article published successfully")
    else
      render_validation_error(@article)
    end
  end

  # POST /api/v1/kb/articles/:id/unpublish
  def unpublish
    return render_error("Article not found", status: :not_found) unless @article

    if @article.update(status: "draft", published_at: nil)
      render_success({
        article: serialize_article_admin(@article)
      }, "Article unpublished successfully")
    else
      render_validation_error(@article)
    end
  end

  # GET /api/v1/kb/articles/search
  def search
    query = params[:q]
    return render_error("Search query is required", status: :bad_request) if query.blank?

    articles = KnowledgeBaseArticle.published.public_articles
    articles = articles.search_by_text(query) if query.present?
    articles = apply_filters(articles)
    articles = articles.includes(:author, :category, :tags).page(params[:page]).per(params[:per_page] || 20)

    render_success({
      query: query,
      articles: articles.map { |article| serialize_article_summary(article) },
      pagination: pagination_meta(articles)
    })
  end

  # GET /api/v1/kb/articles/analytics
  def analytics
    articles = KnowledgeBaseArticle.includes(:article_views)
    period = params[:period]&.to_i&.days || 30.days

    analytics_data = {
      total_articles: articles.count,
      published_articles: articles.published.count,
      draft_articles: articles.where(status: "draft").count,
      total_views: KnowledgeBaseArticleView.for_period(period.ago, Time.current).count,
      top_articles: KnowledgeBaseArticleView.top_articles(limit: 10, period: period),
      views_by_day: daily_views_breakdown(period)
    }

    render_success(analytics_data, "Analytics retrieved successfully")
  end

  # PATCH /api/v1/kb/articles/bulk
  def bulk_update
    article_ids = params[:article_ids]
    return render_error("No article IDs provided", status: :bad_request) if article_ids.blank?

    articles = KnowledgeBaseArticle.where(id: article_ids)
    return render_error("No articles found", status: :not_found) if articles.empty?

    # Check permissions for all articles
    unauthorized_articles = articles.reject { |article| article.editable_by?(current_user) }
    if unauthorized_articles.any?
      return render_error("Access denied for some articles", status: :forbidden)
    end

    updated_count = 0
    update_params = bulk_update_params

    articles.each do |article|
      if article.update(update_params)
        updated_count += 1
      end
    end

    render_success({
      updated_count: updated_count
    }, "#{updated_count} articles updated successfully")
  rescue StandardError => e
    render_error("Bulk update failed: #{e.message}", status: :internal_server_error)
  end

  # DELETE /api/v1/kb/articles/bulk
  def bulk_delete
    article_ids = params[:article_ids]
    return render_error("No article IDs provided", status: :bad_request) if article_ids.blank?

    articles = KnowledgeBaseArticle.where(id: article_ids)
    return render_error("No articles found", status: :not_found) if articles.empty?

    # Check permissions for all articles
    unauthorized_articles = articles.reject { |article| article.editable_by?(current_user) }
    if unauthorized_articles.any?
      return render_error("Access denied for some articles", status: :forbidden)
    end

    deleted_count = 0
    articles.each do |article|
      if article.destroy
        deleted_count += 1
      end
    end

    render_success({
      deleted_count: deleted_count
    }, "#{deleted_count} articles deleted successfully")
  rescue StandardError => e
    render_error("Bulk delete failed: #{e.message}", status: :internal_server_error)
  end

  private

  def set_article
    @article = KnowledgeBaseArticle.find_by(id: params[:id]) ||
               KnowledgeBaseArticle.find_by(slug: params[:id])
  end

  def editing_mode?
    params[:admin] == "true" || params[:edit] == "true" || request.path.include?("/admin")
  end

  def can_edit_kb?
    current_user&.has_permission?("kb.update") ||
    current_user&.has_permission?("kb.manage")
  end

  def can_publish_kb?
    current_user&.has_permission?("kb.publish") ||
    current_user&.has_permission?("kb.manage")
  end

  def can_manage_kb?
    current_user&.has_permission?("kb.manage")
  end

  def authorize_kb_edit
    render_error("Access denied", status: :forbidden) unless can_edit_kb?
  end

  def authorize_kb_publish
    render_error("Access denied", status: :forbidden) unless can_publish_kb?
  end

  def authorize_kb_manage
    render_error("Access denied", status: :forbidden) unless can_manage_kb?
  end

  def apply_filters(articles)
    articles = articles.in_category(params[:category_id]) if params[:category_id].present?
    articles = articles.featured if params[:featured] == "true"
    articles = articles.recent if params[:sort] == "recent"
    articles = articles.popular if params[:sort] == "popular"

    if params[:tags].present?
      tag_names = params[:tags].split(",")
      articles = articles.joins(:tags).where(knowledge_base_tags: { name: tag_names })
    end

    articles
  end

  def apply_admin_filters(articles)
    articles = articles.where("title ILIKE ?", "%#{params[:search]}%") if params[:search].present?
    articles = articles.where(status: params[:status]) if params[:status].present?
    articles = articles.in_category(params[:category_id]) if params[:category_id].present?
    articles = articles.by_author(params[:author_id]) if params[:author_id].present?
    articles = articles.where(is_public: params[:is_public] == "true") if params[:is_public].present?
    articles = articles.where(is_featured: params[:is_featured] == "true") if params[:is_featured].present?

    case params[:sort]
    when "recent"
      articles.recent
    when "popular"
      articles.popular
    when "title"
      articles.order(:title)
    else
      articles.order(updated_at: :desc)
    end
  end

  def handle_tag_assignment(article)
    tag_names = params[:article][:tag_names]
    article.tag_names = tag_names.is_a?(Array) ? tag_names : tag_names.split(",").map(&:strip)
    article.save
  end

  def article_params
    params.require(:article).permit(
      :title, :slug, :content, :excerpt, :category_id, :status, :is_public, :is_featured,
      :sort_order, :meta_title, :meta_description, tag_names: [], metadata: {}
    )
  end

  def bulk_update_params
    params.permit(:status, :category_id, :is_featured, :is_public)
  end

  def serialize_article_summary(article)
    {
      id: article.id,
      title: article.title,
      slug: article.slug,
      excerpt: article.excerpt,
      author_name: article.author.full_name,
      category: {
        id: article.category.id,
        name: article.category.name,
        slug: article.category.slug
      },
      published_at: article.published_at,
      reading_time: article.reading_time,
      views_count: article.views_count,
      likes_count: article.likes_count,
      is_featured: article.is_featured,
      tags: article.tags.map(&:name)
    }
  end

  def serialize_article_full(article)
    serialize_article_summary(article).merge(
      content: article.content,
      metadata: article.metadata,
      attachments: article.attachments.map { |attachment| serialize_attachment(attachment) },
      comments_enabled: true,
      can_edit: article.editable_by?(current_user)
    )
  end

  def serialize_article_admin(article)
    {
      id: article.id,
      title: article.title,
      slug: article.slug,
      status: article.status,
      is_public: article.is_public,
      is_featured: article.is_featured,
      author_name: article.author.full_name,
      category: {
        id: article.category.id,
        name: article.category.name
      },
      views_count: article.views_count,
      likes_count: article.likes_count,
      comments_count: article.comments.approved.count,
      created_at: article.created_at,
      updated_at: article.updated_at,
      published_at: article.published_at,
      tags: article.tags.map(&:name)
    }
  end

  def serialize_article_detailed(article)
    serialize_article_admin(article).merge(
      content: article.content,
      excerpt: article.excerpt,
      sort_order: article.sort_order,
      reading_time: article.reading_time,
      meta_title: article.meta_title,
      meta_description: article.meta_description,
      metadata: article.metadata,
      attachments: article.attachments.map { |attachment| serialize_attachment(attachment) }
    )
  end

  def serialize_attachment(attachment)
    {
      id: attachment.id,
      filename: attachment.filename,
      content_type: attachment.content_type,
      file_size: attachment.human_file_size,
      download_count: attachment.download_count
    }
  end

  def calculate_article_stats
    {
      total: KnowledgeBaseArticle.count,
      published: KnowledgeBaseArticle.published.count,
      draft: KnowledgeBaseArticle.where(status: "draft").count,
      review: KnowledgeBaseArticle.where(status: "review").count,
      archived: KnowledgeBaseArticle.where(status: "archived").count
    }
  end

  def daily_views_breakdown(period)
    KnowledgeBaseArticleView.for_period(period.ago, Time.current)
      .group_by_day(:created_at)
      .count
      .transform_keys { |date| date.strftime("%Y-%m-%d") }
  end

  def pagination_meta(collection)
    {
      current_page: collection.current_page,
      total_pages: collection.total_pages,
      total_count: collection.total_count,
      per_page: collection.limit_value
    }
  end
end
