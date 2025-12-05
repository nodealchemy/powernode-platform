# frozen_string_literal: true

class Api::V1::Kb::TagsController < ApplicationController
  skip_before_action :authenticate_request, only: [:index, :articles]
  
  # GET /api/v1/kb/tags
  def index
    tags = KnowledgeBaseTag.popular.limit(50)
    
    render_success(
      data: tags.map { |tag| serialize_tag(tag) },
      message: 'Tags retrieved successfully'
    )
  end

  # GET /api/v1/kb/tags/:id/articles
  def articles
    tag = KnowledgeBaseTag.find_by(id: params[:id]) || 
          KnowledgeBaseTag.find_by(slug: params[:id])
    
    return render_error('Tag not found', status: :not_found) unless tag

    articles = tag.articles.published.public_articles
      .includes(:author, :category, :tags)
      .page(params[:page])
      .per(params[:per_page] || 20)

    render_success(
      data: {
        tag: serialize_tag(tag),
        articles: articles.map { |article| serialize_article_summary(article) },
        pagination: pagination_meta(articles)
      },
      message: 'Tag articles retrieved successfully'
    )
  end

  private

  def serialize_tag(tag)
    {
      id: tag.id,
      name: tag.name,
      slug: tag.slug,
      description: tag.description,
      color: tag.color,
      usage_count: tag.usage_count
    }
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
        name: article.category.name
      },
      published_at: article.published_at,
      reading_time: article.reading_time,
      views_count: article.views_count
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