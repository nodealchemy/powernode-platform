# frozen_string_literal: true

class Api::V1::PagesController < ApplicationController
  # Public endpoint - no authentication required for viewing published pages
  skip_before_action :authenticate_request, only: [:index, :show]
  
  before_action :set_page, only: [:show]

  # GET /api/v1/pages/:slug
  def show
    unless @page.published?
      render_error("The requested page is not available", status: :not_found)
      return
    end

    render_success({
      id: @page.id,
      title: @page.title,
      slug: @page.slug,
      content: @page.content,
      rendered_content: @page.rendered_content,
      meta_description: @page.meta_description,
      meta_keywords: @page.meta_keywords,
      published_at: @page.published_at,
      word_count: @page.word_count,
      estimated_read_time: @page.estimated_read_time,
      seo: {
        title: @page.seo_title,
        description: @page.seo_description,
        keywords: @page.seo_keywords_array
      }
    })
  end

  # GET /api/v1/pages (public index for published pages)
  def index
    pages = Page.published.recent
    
    # Simple pagination without using pagination_params method
    page = 1
    per_page = 20
    
    if params[:page].present?
      page = params[:page].to_i
    end
    
    if params[:per_page].present?
      per_page = [[params[:per_page].to_i, 1].max, 100].min
    end
    
    page = [page, 1].max
    
    pages = pages.limit(per_page).offset((page - 1) * per_page)
    
    total_count = Page.published.count
    total_pages = (total_count.to_f / per_page).ceil

    render_success({
      pages: pages.map do |page|
        {
          id: page.id,
          title: page.title,
          slug: page.slug,
          meta_description: page.meta_description,
          published_at: page.published_at,
          word_count: page.word_count,
          estimated_read_time: page.estimated_read_time,
          excerpt: page.content.to_s.truncate(200)
        }
      end,
      meta: {
        current_page: page,
        per_page: per_page,
        total_count: total_count,
        total_pages: total_pages
      }
    })
  end

  private

  def set_page
    @page = Page.find_by!(slug: params[:slug])
  rescue ActiveRecord::RecordNotFound
    render_error("The requested page could not be found", status: :not_found)
  end
end