# frozen_string_literal: true

class Api::V1::Kb::CategoriesController < ApplicationController
  skip_before_action :authenticate_request, only: [:index, :show]
  before_action :set_category, only: [:show]

  # GET /api/v1/kb/categories
  def index
    categories = KnowledgeBaseCategory.public_categories
      .root_categories
      .includes(:children, :articles)
      .ordered

    render_success(categories.map { |category| serialize_category_with_children(category) })
  end

  # GET /api/v1/kb/categories/:id
  def show
    return render_error('Category not found', :not_found) unless @category&.is_public

    articles = @category.articles
      .published
      .public_articles
      .includes(:author, :tags)
      .ordered

    render_success({
      category: serialize_category(@category),
      articles: articles.map { |article| serialize_article_summary(article) }
    })
  end

  private

  def set_category
    @category = KnowledgeBaseCategory.find_by(id: params[:id])
  end

  def serialize_category(category)
    {
      id: category.id,
      name: category.name,
      slug: category.slug,
      description: category.description,
      full_path: category.full_path,
      article_count: category.article_count
    }
  end

  def serialize_category_with_children(category)
    serialize_category(category).merge(
      children: category.children.public_categories.ordered.map { |child| serialize_category(child) }
    )
  end

  def serialize_article_summary(article)
    {
      id: article.id,
      title: article.title,
      slug: article.slug,
      excerpt: article.excerpt,
      author_name: article.author.full_name,
      published_at: article.published_at,
      reading_time: article.reading_time,
      views_count: article.views_count,
      is_featured: article.is_featured,
      tags: article.tags.map(&:name)
    }
  end
end