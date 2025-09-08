# frozen_string_literal: true

class Api::V1::Kb::CategoriesController < ApplicationController
  skip_before_action :authenticate_request, only: [:index, :show, :tree]
  before_action :set_category, only: [:show, :update, :destroy]
  before_action :authorize_kb_manage, only: [:create, :update, :destroy]

  # GET /api/v1/kb/categories
  def index
    if editing_mode?
      # Admin view - all categories for editing
      categories = KnowledgeBaseCategory.includes(:children, :articles, :parent)
      categories = categories.where('name ILIKE ?', "%#{params[:search]}%") if params[:search].present?
      categories = categories.ordered.page(params[:page]).per(params[:per_page] || 50)

      render_success({
        categories: categories.map { |category| serialize_category_admin(category) },
        pagination: pagination_meta(categories)
      })
    else
      # Public view - only public categories
      categories = KnowledgeBaseCategory.public_categories
        .root_categories
        .includes(:children, :articles)
        .ordered

      render_success(categories.map { |category| serialize_category_with_children(category) })
    end
  end

  # GET /api/v1/kb/categories/tree
  def tree
    if can_manage_kb?
      # Full tree for admin
      categories = KnowledgeBaseCategory.includes(:children, :articles).ordered
    else
      # Public tree only
      categories = KnowledgeBaseCategory.public_categories.includes(:children, :articles).ordered
    end

    render_success(build_category_tree(categories.root_categories))
  end

  # GET /api/v1/kb/categories/:id
  def show
    return render_error('Category not found', :not_found) unless @category

    if editing_mode?
      # Admin view - detailed category info for editing
      return render_error('Access denied', :forbidden) unless can_manage_kb?

      render_success({
        category: serialize_category_detailed(@category)
      })
    else
      # Public view - category with articles
      return render_error('Category not found', :not_found) unless @category.is_public

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
  end

  # POST /api/v1/kb/categories
  def create
    category = KnowledgeBaseCategory.new(category_params)

    if category.save
      render_success({
        category: serialize_category_admin(category)
      }, 'Category created successfully')
    else
      render_validation_error(category)
    end
  end

  # PATCH /api/v1/kb/categories/:id
  def update
    return render_error('Category not found', :not_found) unless @category

    if @category.update(category_params)
      render_success({
        category: serialize_category_admin(@category)
      }, 'Category updated successfully')
    else
      render_validation_error(@category)
    end
  end

  # DELETE /api/v1/kb/categories/:id
  def destroy
    return render_error('Category not found', :not_found) unless @category
    return render_error('Cannot delete category with articles', :bad_request) if @category.articles.any?

    @category.destroy
    render_success(message: 'Category deleted successfully')
  end

  private

  def set_category
    @category = KnowledgeBaseCategory.find_by(id: params[:id])
  end

  def editing_mode?
    params[:admin] == 'true' || params[:edit] == 'true' || 
    request.path.include?('/admin') || can_manage_kb?
  end

  def can_manage_kb?
    current_user&.has_permission?('kb.manage')
  end

  def authorize_kb_manage
    return render_error('Access denied', :forbidden) unless can_manage_kb?
  end

  def category_params
    params.require(:category).permit(
      :name, :slug, :description, :parent_id, :is_public, :sort_order, 
      :icon, :color, metadata: {}
    )
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

  def serialize_category_admin(category)
    {
      id: category.id,
      name: category.name,
      slug: category.slug,
      description: category.description,
      parent_id: category.parent_id,
      parent_name: category.parent&.name,
      full_path: category.full_path,
      is_public: category.is_public,
      sort_order: category.sort_order,
      article_count: category.article_count,
      total_article_count: category.total_article_count,
      icon: category.icon,
      color: category.color,
      children_count: category.children.count,
      created_at: category.created_at,
      updated_at: category.updated_at,
      metadata: category.metadata
    }
  end

  def serialize_category_detailed(category)
    serialize_category_admin(category).merge(
      children: category.children.ordered.map { |child| serialize_category_admin(child) },
      recent_articles: category.articles.recent.limit(5).map { |article| serialize_article_summary(article) }
    )
  end

  def build_category_tree(categories)
    categories.map do |category|
      {
        id: category.id,
        name: category.name,
        slug: category.slug,
        article_count: category.article_count,
        is_public: category.is_public,
        children: build_category_tree(category.children.ordered)
      }
    end
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

  def pagination_meta(collection)
    {
      current_page: collection.current_page,
      total_pages: collection.total_pages,
      total_count: collection.total_count,
      per_page: collection.limit_value
    }
  end
end