# frozen_string_literal: true

class Api::V1::MarketplaceListingsController < ApplicationController
  include AuditLogging
  
  skip_before_action :authenticate_request, only: [:index, :show, :categories]
  before_action :authenticate_optional, only: [:index, :show, :categories]
  # Authentication is handled by ApplicationController's before_action :authenticate_request (except for public endpoints)
  before_action :set_app, only: [:create, :update, :destroy, :submit, :approve, :reject, :feature, :unfeature]
  before_action :set_listing, only: [:show, :update, :destroy, :submit, :approve, :reject, :feature, :unfeature]
  before_action :authorize_listing_access, only: [:update, :destroy, :submit]
  before_action :authorize_review_access, only: [:approve, :reject]
  before_action :authorize_admin_access, only: [:feature, :unfeature]
  
  def index
    listings = MarketplaceListing.includes(:app)
    
    # For public access, only show approved listings
    if current_user.nil?
      listings = listings.approved
    else
      # Apply filters for authenticated users
      listings = listings.approved if params[:status] == 'approved'
      listings = listings.pending_review if params[:status] == 'pending'
      listings = listings.rejected if params[:status] == 'rejected'
      listings = listings.published if params[:status] == 'published'
    end
    
    listings = listings.featured if params[:featured] == 'true'
    listings = listings.by_category(params[:category]) if params[:category].present?
    listings = listings.with_tags(params[:tags].split(',')) if params[:tags].present?
    listings = listings.search(params[:search]) if params[:search].present?
    
    # Apply sorting
    case params[:sort]
    when 'title'
      listings = listings.order(:title)
    when 'category'
      listings = listings.order(:category, :title)
    when 'recent'
      listings = listings.recent
    when 'popular'
      listings = listings.popular
    else
      listings = listings.recent
    end
    
    # Manual pagination  
    pagination = pagination_params
    page = pagination[:page]
    per_page = pagination[:per_page]
    
    # Get total count before applying limit/offset
    total_count = listings.count
    total_pages = (total_count.to_f / per_page).ceil
    
    # Apply pagination
    listings = listings.limit(per_page).offset((page - 1) * per_page)
    
    render json: {
      success: true,
      data: listings.map { |listing| listing_data(listing) },
      pagination: {
        current_page: page,
        total_pages: total_pages,
        total_count: total_count,
        per_page: per_page
      }
    }, status: :ok
  end
  
  def show
    render json: {
      success: true,
      data: listing_data(@listing, detailed: true)
    }, status: :ok
  end
  
  def create
    @listing = @app.build_marketplace_listing(listing_params)
    @listing.review_status = 'pending'
    
    if @listing.save
      # TODO: Add audit logging when available
      Rails.logger.info "Marketplace listing created: #{@listing.title}"
      
      render json: {
        success: true,
        data: listing_data(@listing, detailed: true),
        message: 'Marketplace listing created successfully'
      }, status: :created
    else
      render json: {
        success: false,
        error: 'Failed to create marketplace listing',
        details: @listing.errors.full_messages
      }, status: :unprocessable_content
    end
  end
  
  def update
    if @listing.update(listing_params)
      # TODO: Add audit logging when available
      Rails.logger.info "Marketplace listing updated: #{@listing.title}"
      
      render json: {
        success: true,
        data: listing_data(@listing, detailed: true),
        message: 'Marketplace listing updated successfully'
      }, status: :ok
    else
      render json: {
        success: false,
        error: 'Failed to update marketplace listing',
        details: @listing.errors.full_messages
      }, status: :unprocessable_content
    end
  end
  
  def destroy
    title = @listing.title
    app_id = @listing.app_id
    
    if @listing.destroy
      # TODO: Add audit logging when available
      Rails.logger.info "Marketplace listing deleted: #{title}"
      
      render json: {
        success: true,
        message: 'Marketplace listing deleted successfully'
      }, status: :ok
    else
      render json: {
        success: false,
        error: 'Failed to delete marketplace listing',
        details: @listing.errors.full_messages
      }, status: :unprocessable_content
    end
  end
  
  def submit
    return render_error('Listing must be rejected to resubmit', :unprocessable_content) unless @listing.rejected?
    
    if @listing.resubmit!
      # TODO: Add audit logging when available
      Rails.logger.info "Marketplace listing resubmitted: #{@listing.title}"
      
      render json: {
        success: true,
        data: listing_data(@listing, detailed: true),
        message: 'Marketplace listing resubmitted successfully'
      }, status: :ok
    else
      render json: {
        success: false,
        error: 'Failed to resubmit marketplace listing',
        details: @listing.errors.full_messages
      }, status: :unprocessable_content
    end
  end
  
  def approve
    reviewer = current_user.name || current_user.email
    notes = params[:notes]
    
    if @listing.approve!(reviewer, notes)
      # TODO: Add audit logging when available
      Rails.logger.info "Marketplace listing approved: #{@listing.title} by #{reviewer}"
      
      render json: {
        success: true,
        data: listing_data(@listing, detailed: true),
        message: 'Marketplace listing approved successfully'
      }, status: :ok
    else
      render json: {
        success: false,
        error: 'Failed to approve marketplace listing',
        details: @listing.errors.full_messages
      }, status: :unprocessable_content
    end
  end
  
  def reject
    reviewer = current_user.name || current_user.email
    notes = params[:notes]
    
    return render_error('Rejection notes are required', :bad_request) if notes.blank?
    
    if @listing.reject!(reviewer, notes)
      # TODO: Add audit logging when available
      Rails.logger.info "Marketplace listing rejected: #{@listing.title} by #{reviewer}"
      
      render json: {
        success: true,
        data: listing_data(@listing, detailed: true),
        message: 'Marketplace listing rejected'
      }, status: :ok
    else
      render json: {
        success: false,
        error: 'Failed to reject marketplace listing',
        details: @listing.errors.full_messages
      }, status: :unprocessable_content
    end
  end
  
  def feature
    if @listing.feature!
      # TODO: Add audit logging when available
      Rails.logger.info "Marketplace listing featured: #{@listing.title}"
      
      render json: {
        success: true,
        data: listing_data(@listing, detailed: true),
        message: 'Marketplace listing featured successfully'
      }, status: :ok
    else
      render json: {
        success: false,
        error: 'Failed to feature marketplace listing',
        details: @listing.errors.full_messages
      }, status: :unprocessable_content
    end
  end
  
  def unfeature
    if @listing.unfeature!
      # TODO: Add audit logging when available
      Rails.logger.info "Marketplace listing unfeatured: #{@listing.title}"
      
      render json: {
        success: true,
        data: listing_data(@listing, detailed: true),
        message: 'Marketplace listing unfeatured successfully'
      }, status: :ok
    else
      render json: {
        success: false,
        error: 'Failed to unfeature marketplace listing',
        details: @listing.errors.full_messages
      }, status: :unprocessable_content
    end
  end
  
  def categories
    categories = MarketplaceCategory.active.ordered.map do |category|
      {
        slug: category.slug,
        name: category.name,
        description: category.description,
        icon: category.icon,
        apps_count: category.published_apps_count
      }
    end
    
    render json: {
      success: true,
      data: categories
    }, status: :ok
  end
  
  def analytics
    return render_error('Listing not found', :not_found) unless set_listing
    return render_error('Unauthorized', :forbidden) unless authorize_listing_access
    
    analytics_data = {
      view_count: @listing.view_count,
      subscription_count: @listing.subscription_count,
      conversion_rate: @listing.conversion_rate,
      average_rating: @listing.average_rating,
      review_count: @listing.review_count,
      featured: @listing.featured?,
      category_rank: calculate_category_rank(@listing),
      similar_listings: @listing.similar_listings(5).map { |l| 
        { id: l.id, title: l.title, category: l.category }
      }
    }
    
    render json: {
      success: true,
      data: analytics_data
    }, status: :ok
  end
  
  def screenshots
    listing = MarketplaceListing.find(params[:id])
    
    case request.method
    when 'POST'
      url = params[:url]
      caption = params[:caption]
      
      return render_error('Screenshot URL is required', :bad_request) if url.blank?
      
      if listing.add_screenshot(url, caption)
        render json: {
          success: true,
          data: { screenshots: listing.screenshots },
          message: 'Screenshot added successfully'
        }, status: :ok
      else
        render_error('Failed to add screenshot', :unprocessable_content)
      end
      
    when 'DELETE'
      index = params[:index]&.to_i
      
      return render_error('Screenshot index is required', :bad_request) if index.nil?
      
      if listing.remove_screenshot(index)
        render json: {
          success: true,
          data: { screenshots: listing.screenshots },
          message: 'Screenshot removed successfully'
        }, status: :ok
      else
        render_error('Failed to remove screenshot', :unprocessable_content)
      end
      
    when 'PATCH'
      new_order = params[:order]
      
      return render_error('Screenshot order is required', :bad_request) if new_order.blank?
      
      if listing.reorder_screenshots(new_order)
        render json: {
          success: true,
          data: { screenshots: listing.screenshots },
          message: 'Screenshots reordered successfully'
        }, status: :ok
      else
        render_error('Failed to reorder screenshots', :unprocessable_content)
      end
    end
  end
  
  private
  
  def set_app
    return render_error('Authentication required', :unauthorized) unless current_account
    
    @app = current_account.apps.find_by(id: params[:app_id])
    render_error('App not found', :not_found) unless @app
  end
  
  def set_listing
    if params[:app_id]
      @listing = @app.marketplace_listing
    else
      @listing = MarketplaceListing.find_by(id: params[:id])
    end
    render_error('Marketplace listing not found', :not_found) unless @listing
  end
  
  def authorize_listing_access
    return true if @listing.app.account == current_account
    return true if current_user.has_permission?('marketplace.manage')
    
    render_error('Unauthorized to access this listing', :forbidden)
    false
  end
  
  def authorize_review_access
    return true if current_user.has_permission?('marketplace.review')
    return true if current_user.has_permission?('system.admin')
    
    render_error('Unauthorized to review listings', :forbidden)
    false
  end
  
  def authorize_admin_access
    return true if current_user.has_permission?('marketplace.admin')
    return true if current_user.has_permission?('system.admin')
    
    render_error('Unauthorized to perform admin actions', :forbidden)
    false
  end
  
  def listing_params
    params.require(:marketplace_listing).permit(
      :title, :short_description, :long_description, :category,
      :documentation_url, :support_url, :homepage_url,
      tags: [], screenshots: []
    )
  end
  
  def listing_data(listing, detailed: false)
    data = {
      id: listing.id,
      title: listing.title,
      short_description: listing.short_description,
      category: listing.category,
      tags: listing.tags,
      review_status: listing.review_status,
      featured: listing.featured?,
      published_at: listing.published_at,
      primary_screenshot: listing.primary_screenshot,
      created_at: listing.created_at,
      updated_at: listing.updated_at,
      app: {
        id: listing.app.id,
        name: listing.app.name,
        slug: listing.app.slug,
        status: listing.app.status,
        app_plans: listing.app.app_plans.active.public_plans.map { |plan|
          {
            id: plan.id,
            name: plan.name,
            slug: plan.slug,
            price_cents: plan.price_cents,
            formatted_price: plan.formatted_price,
            billing_interval: plan.billing_interval,
            description: plan.description,
            features: plan.features,
            is_popular: plan.metadata&.dig('popular') || false
          }
        }
      }
    }
    
    if detailed
      data.merge!(
        long_description: listing.long_description,
        documentation_url: listing.documentation_url,
        support_url: listing.support_url,
        homepage_url: listing.homepage_url,
        screenshots: listing.screenshots,
        screenshot_urls: listing.screenshot_urls,
        formatted_tags: listing.formatted_tags,
        tag_list: listing.tag_list,
        review_notes: listing.review_notes,
        view_count: listing.view_count,
        subscription_count: listing.subscription_count,
        conversion_rate: listing.conversion_rate,
        average_rating: listing.average_rating,
        review_count: listing.review_count,
        similar_listings: listing.similar_listings(3).map { |l| 
          { id: l.id, title: l.title, category: l.category }
        },
        competing_listings: listing.competing_listings(3).map { |l| 
          { id: l.id, title: l.title, tags: l.tags }
        }
      )
    end
    
    data
  end
  
  def calculate_category_rank(listing)
    category_listings = MarketplaceListing.published
                                         .by_category(listing.category)
                                         .order('view_count DESC, created_at ASC')
    
    category_listings.pluck(:id).index(listing.id)&.+(1) || 0
  end
  
  def render_error(message, status)
    render json: {
      success: false,
      error: message
    }, status: status
  end
end