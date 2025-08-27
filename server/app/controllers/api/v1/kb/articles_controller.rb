# frozen_string_literal: true

class Api::V1::Kb::ArticlesController < ApplicationController
  skip_before_action :authenticate_request, only: [:index, :show, :search]
  before_action :set_article, only: [:show]

  # GET /api/v1/kb/articles
  def index
    articles = KnowledgeBaseArticle.published.public_articles
    articles = apply_filters(articles)
    articles = articles.includes(:author, :category, :tags).page(params[:page]).per(params[:per_page] || 20)

    render_success({
      articles: articles.map { |article| serialize_article_summary(article) },
      pagination: pagination_meta(articles)
    })
  end

  # GET /api/v1/kb/articles/:id
  def show
    return render_error('Article not found', :not_found) unless @article
    return render_error('Access denied', :forbidden) unless @article.viewable_by?(current_user)

    # Record view
    @article.record_view!(
      user: current_user,
      session_id: session.id.to_s.presence || SecureRandom.hex(16),
      ip_address: request.remote_ip,
      user_agent: request.user_agent
    )

    render_success({
      article: serialize_article_full(@article),
      related_articles: @article.related_articles.map { |article| serialize_article_summary(article) }
    })
  end

  # GET /api/v1/kb/articles/search
  def search
    query = params[:q]
    return render_error('Search query is required', :bad_request) if query.blank?

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

  private

  def set_article
    @article = KnowledgeBaseArticle.find_by(id: params[:id]) || 
               KnowledgeBaseArticle.find_by(slug: params[:id])
  end

  def apply_filters(articles)
    articles = articles.in_category(params[:category_id]) if params[:category_id].present?
    articles = articles.featured if params[:featured] == 'true'
    articles = articles.recent if params[:sort] == 'recent'
    articles = articles.popular if params[:sort] == 'popular'
    
    if params[:tags].present?
      tag_names = params[:tags].split(',')
      articles = articles.joins(:tags).where(knowledge_base_tags: { name: tag_names })
    end

    articles
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
      comments_enabled: true, # Could be made configurable
      can_edit: article.editable_by?(current_user)
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

  def pagination_meta(collection)
    {
      current_page: collection.current_page,
      total_pages: collection.total_pages,
      total_count: collection.total_count,
      per_page: collection.limit_value
    }
  end
end