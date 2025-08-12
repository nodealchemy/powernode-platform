class Api::V1::Admin::PagesController < ApplicationController
  # Admin endpoints - authentication required
  before_action :ensure_admin_access!
  before_action :set_page, only: [ :show, :update, :destroy ]

  # GET /api/v1/admin/pages
  def index
    pages = Page.includes(:user).order(created_at: :desc)

    # Filter by status if provided
    if params[:status].present? && %w[draft published].include?(params[:status])
      pages = pages.where(status: params[:status])
    end

    # Filter by author if provided
    if params[:author_id].present?
      pages = pages.where(author_id: params[:author_id])
    end

    # Search by title or content if provided
    if params[:search].present?
      search_term = "%#{params[:search]}%"
      pages = pages.where("title ILIKE ? OR content ILIKE ?", search_term, search_term)
    end

    # Pagination
    pagination = pagination_params
    pages = pages.limit(pagination[:per_page]).offset((pagination[:page] - 1) * pagination[:per_page])

    total_count = Page.count
    total_pages = (total_count.to_f / pagination[:per_page]).ceil

    render json: {
      data: pages.map do |page|
        {
          id: page.id,
          title: page.title,
          slug: page.slug,
          status: page.status,
          meta_description: page.meta_description,
          meta_keywords: page.meta_keywords,
          author: {
            id: page.user.id,
            name: page.user.full_name,
            email: page.user.email
          },
          published_at: page.published_at,
          word_count: page.word_count,
          estimated_read_time: page.estimated_read_time,
          created_at: page.created_at,
          updated_at: page.updated_at,
          excerpt: page.content.to_s.truncate(200)
        }
      end,
      meta: {
        current_page: pagination[:page],
        per_page: pagination[:per_page],
        total_count: total_count,
        total_pages: total_pages,
        filters: {
          status: params[:status],
          author_id: params[:author_id],
          search: params[:search]
        }
      }
    }
  end

  # GET /api/v1/admin/pages/:id
  def show
    render json: {
      data: {
        id: @page.id,
        title: @page.title,
        slug: @page.slug,
        content: @page.content,
        rendered_content: @page.rendered_content,
        meta_description: @page.meta_description,
        meta_keywords: @page.meta_keywords,
        status: @page.status,
        author: {
          id: @page.user.id,
          name: @page.user.full_name,
          email: @page.user.email
        },
        published_at: @page.published_at,
        word_count: @page.word_count,
        estimated_read_time: @page.estimated_read_time,
        created_at: @page.created_at,
        updated_at: @page.updated_at,
        seo: {
          title: @page.seo_title,
          description: @page.seo_description,
          keywords: @page.seo_keywords_array
        }
      }
    }
  end

  # POST /api/v1/admin/pages
  def create
    @page = Page.new(page_params)
    @page.author = current_user

    if @page.save
      render json: {
        data: serialize_page(@page),
        message: "Page created successfully"
      }, status: :created
    else
      render json: {
        error: "Page creation failed",
        details: @page.errors.full_messages
      }, status: :unprocessable_content
    end
  end

  # PATCH/PUT /api/v1/admin/pages/:id
  def update
    if @page.update(page_params)
      render json: {
        data: serialize_page(@page),
        message: "Page updated successfully"
      }
    else
      render json: {
        error: "Page update failed",
        details: @page.errors.full_messages
      }, status: :unprocessable_content
    end
  end

  # DELETE /api/v1/admin/pages/:id
  def destroy
    @page.destroy!
    render json: {
      message: "Page deleted successfully"
    }
  rescue ActiveRecord::RecordNotDestroyed
    render json: {
      error: "Page deletion failed",
      details: @page.errors.full_messages
    }, status: :unprocessable_content
  end

  # POST /api/v1/admin/pages/:id/publish
  def publish
    set_page
    if @page.publish!
      render json: {
        data: serialize_page(@page),
        message: "Page published successfully"
      }
    else
      render json: {
        error: "Page publication failed",
        details: @page.errors.full_messages
      }, status: :unprocessable_content
    end
  end

  # POST /api/v1/admin/pages/:id/unpublish
  def unpublish
    set_page
    if @page.unpublish!
      render json: {
        data: serialize_page(@page),
        message: "Page unpublished successfully"
      }
    else
      render json: {
        error: "Page unpublishing failed",
        details: @page.errors.full_messages
      }, status: :unprocessable_content
    end
  end

  # POST /api/v1/admin/pages/:id/duplicate
  def duplicate
    set_page

    new_page = @page.dup
    new_page.title = "#{@page.title} (Copy)"
    new_page.slug = nil  # Will be auto-generated
    new_page.status = "draft"
    new_page.published_at = nil
    new_page.author = current_user

    if new_page.save
      render json: {
        data: serialize_page(new_page),
        message: "Page duplicated successfully"
      }, status: :created
    else
      render json: {
        error: "Page duplication failed",
        details: new_page.errors.full_messages
      }, status: :unprocessable_content
    end
  end

  private

  def set_page
    @page = Page.find(params[:id])
  end

  def page_params
    params.require(:page).permit(
      :title, :slug, :content, :meta_description,
      :meta_keywords, :status
    )
  end

  def ensure_admin_access!
    unless current_user.admin? || current_user.owner?
      render json: {
        error: "Access denied",
        message: "You don't have permission to access this resource"
      }, status: :forbidden
    end
  end

  def serialize_page(page)
    {
      id: page.id,
      title: page.title,
      slug: page.slug,
      content: page.content,
      rendered_content: page.rendered_content,
      meta_description: page.meta_description,
      meta_keywords: page.meta_keywords,
      status: page.status,
      author: {
        id: page.user.id,
        name: page.user.full_name,
        email: page.user.email
      },
      published_at: page.published_at,
      word_count: page.word_count,
      estimated_read_time: page.estimated_read_time,
      created_at: page.created_at,
      updated_at: page.updated_at
    }
  end
end
