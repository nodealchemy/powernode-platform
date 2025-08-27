# frozen_string_literal: true

class Api::V1::Admin::Kb::ArticlesController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_kb_access
  before_action :set_article, only: [:show, :update, :destroy, :publish, :unpublish]

  # GET /api/v1/admin/kb/articles
  def index
    articles = KnowledgeBaseArticle.includes(:author, :category, :tags)
    articles = apply_admin_filters(articles)
    articles = articles.page(params[:page]).per(params[:per_page] || 20)

    render_success(
      data: {
        articles: articles.map { |article| serialize_article_admin(article) },
        pagination: pagination_meta(articles),
        stats: calculate_article_stats
      },
      message: 'Articles retrieved successfully'
    )
  end

  # GET /api/v1/admin/kb/articles/:id
  def show
    return render_error('Article not found', :not_found) unless @article

    render_success(
      data: serialize_article_detailed(@article),
      message: 'Article retrieved successfully'
    )
  end

  # POST /api/v1/admin/kb/articles
  def create
    article = KnowledgeBaseArticle.new(article_params)
    article.author = current_user

    if article.save
      handle_tag_assignment(article) if params[:article][:tag_names].present?
      
      render_success(
        data: serialize_article_admin(article.reload),
        message: 'Article created successfully'
      )
    else
      render_validation_error(article)
    end
  end

  # PATCH /api/v1/admin/kb/articles/:id
  def update
    return render_error('Article not found', :not_found) unless @article
    return render_error('Access denied', :forbidden) unless @article.editable_by?(current_user)

    if @article.update(article_params)
      handle_tag_assignment(@article) if params[:article][:tag_names].present?
      
      render_success(
        data: serialize_article_admin(@article.reload),
        message: 'Article updated successfully'
      )
    else
      render_validation_error(@article)
    end
  end

  # DELETE /api/v1/admin/kb/articles/:id
  def destroy
    return render_error('Article not found', :not_found) unless @article
    return render_error('Access denied', :forbidden) unless @article.editable_by?(current_user)

    @article.destroy
    render_success(message: 'Article deleted successfully')
  end

  # POST /api/v1/admin/kb/articles/:id/publish
  def publish
    return render_error('Article not found', :not_found) unless @article

    if @article.update(status: 'published')
      render_success(
        data: serialize_article_admin(@article),
        message: 'Article published successfully'
      )
    else
      render_validation_error(@article)
    end
  end

  # POST /api/v1/admin/kb/articles/:id/unpublish
  def unpublish
    return render_error('Article not found', :not_found) unless @article

    if @article.update(status: 'draft')
      render_success(
        data: serialize_article_admin(@article),
        message: 'Article unpublished successfully'
      )
    else
      render_validation_error(@article)
    end
  end

  # GET /api/v1/admin/kb/articles/analytics
  def analytics
    articles = KnowledgeBaseArticle.includes(:article_views)
    period = params[:period]&.to_i&.days || 30.days

    analytics_data = {
      total_articles: articles.count,
      published_articles: articles.published.count,
      draft_articles: articles.where(status: 'draft').count,
      total_views: KnowledgeBaseArticleView.for_period(period.ago, Time.current).count,
      top_articles: KnowledgeBaseArticleView.top_articles(limit: 10, period: period),
      views_by_day: daily_views_breakdown(period)
    }

    render_success(
      data: analytics_data,
      message: 'Analytics retrieved successfully'
    )
  end

  private

  def set_article
    @article = KnowledgeBaseArticle.find_by(id: params[:id])
  end

  def authorize_kb_access
    return render_error('Access denied', :forbidden) unless current_user.permissions.include?('kb.write') || current_user.permissions.include?('kb.manage')
  end

  def article_params
    params.require(:article).permit(:title, :content, :excerpt, :category_id, :status, :is_public, :is_featured, :sort_order, metadata: {})
  end

  def apply_admin_filters(articles)
    articles = articles.where('title ILIKE ?', "%#{params[:search]}%") if params[:search].present?
    articles = articles.where(status: params[:status]) if params[:status].present?
    articles = articles.in_category(params[:category_id]) if params[:category_id].present?
    articles = articles.by_author(params[:author_id]) if params[:author_id].present?
    articles = articles.where(is_public: params[:is_public] == 'true') if params[:is_public].present?
    articles = articles.where(is_featured: params[:is_featured] == 'true') if params[:is_featured].present?

    case params[:sort]
    when 'recent'
      articles.recent
    when 'popular'
      articles.popular
    when 'title'
      articles.order(:title)
    else
      articles.order(updated_at: :desc)
    end
  end

  def handle_tag_assignment(article)
    tag_names = params[:article][:tag_names]
    article.tag_names = tag_names.is_a?(Array) ? tag_names : tag_names.split(',').map(&:strip)
    article.save
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
      draft: KnowledgeBaseArticle.where(status: 'draft').count,
      review: KnowledgeBaseArticle.where(status: 'review').count,
      archived: KnowledgeBaseArticle.where(status: 'archived').count
    }
  end

  def daily_views_breakdown(period)
    KnowledgeBaseArticleView.for_period(period.ago, Time.current)
      .group_by_day(:created_at)
      .count
      .transform_keys { |date| date.strftime('%Y-%m-%d') }
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