# frozen_string_literal: true

class Api::V1::Admin::Kb::CategoriesController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_kb_access
  before_action :set_category, only: [:show, :update, :destroy]

  # GET /api/v1/admin/kb/categories
  def index
    categories = KnowledgeBaseCategory.includes(:children, :articles)
    categories = categories.where('name ILIKE ?', "%#{params[:search]}%") if params[:search].present?
    categories = categories.ordered.page(params[:page]).per(params[:per_page] || 50)

    render_success(
      data: {
        categories: categories.map { |category| serialize_category_admin(category) },
        pagination: pagination_meta(categories)
      },
      message: 'Categories retrieved successfully'
    )
  end

  # GET /api/v1/admin/kb/categories/:id
  def show
    return render_error('Category not found', :not_found) unless @category

    render_success(
      data: serialize_category_detailed(@category),
      message: 'Category retrieved successfully'
    )
  end

  # POST /api/v1/admin/kb/categories
  def create
    category = KnowledgeBaseCategory.new(category_params)

    if category.save
      render_success(
        data: serialize_category_admin(category),
        message: 'Category created successfully'
      )
    else
      render_validation_error(category)
    end
  end

  # PATCH /api/v1/admin/kb/categories/:id
  def update
    return render_error('Category not found', :not_found) unless @category

    if @category.update(category_params)
      render_success(
        data: serialize_category_admin(@category),
        message: 'Category updated successfully'
      )
    else
      render_validation_error(@category)
    end
  end

  # DELETE /api/v1/admin/kb/categories/:id
  def destroy
    return render_error('Category not found', :not_found) unless @category
    
    if @category.articles.any?
      return render_error('Cannot delete category with articles', :conflict)
    end

    @category.destroy
    render_success(message: 'Category deleted successfully')
  end

  # GET /api/v1/admin/kb/categories/tree
  def tree
    categories = KnowledgeBaseCategory.root_categories.includes(children: :children).ordered

    render_success(
      data: categories.map { |category| serialize_category_tree(category) },
      message: 'Category tree retrieved successfully'
    )
  end

  private

  def set_category
    @category = KnowledgeBaseCategory.find_by(id: params[:id])
  end

  def authorize_kb_access
    return render_error('Access denied', :forbidden) unless current_user.permissions.include?('kb.manage')
  end

  def category_params
    params.require(:category).permit(:name, :description, :parent_id, :sort_order, :is_public, metadata: {})
  end

  def serialize_category_admin(category)
    {
      id: category.id,
      name: category.name,
      slug: category.slug,
      description: category.description,
      parent_id: category.parent_id,
      parent_name: category.parent&.name,
      sort_order: category.sort_order,
      is_public: category.is_public,
      article_count: category.article_count,
      total_article_count: category.article_count(include_descendants: true),
      created_at: category.created_at,
      updated_at: category.updated_at,
      metadata: category.metadata
    }
  end

  def serialize_category_detailed(category)
    serialize_category_admin(category).merge(
      full_path: category.full_path,
      children_count: category.children.count,
      path_names: category.path_names
    )
  end

  def serialize_category_tree(category)
    {
      id: category.id,
      name: category.name,
      slug: category.slug,
      article_count: category.article_count,
      children: category.children.ordered.map { |child| serialize_category_tree(child) }
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