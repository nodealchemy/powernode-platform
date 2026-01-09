# frozen_string_literal: true

class Api::V1::AppReviewsController < ApplicationController
  before_action :authenticate_request, except: [ :index, :show, :summary ]
  before_action :set_app, only: [ :index, :show, :create, :summary ]
  before_action :set_app_review, only: [ :show, :update, :destroy, :vote, :flag, :moderate ]
  before_action :check_permissions, only: [ :update, :destroy, :flag, :moderate ]

  # GET /api/v1/apps/:app_id/reviews
  def index
    @reviews = @app.app_reviews.publicly_visible
                   .includes(:account, :review_media_attachments, :approved_responses)

    # Apply filters
    @reviews = @reviews.by_rating(params[:rating]) if params[:rating].present?
    @reviews = @reviews.with_sentiment(params[:sentiment]) if params[:sentiment].present?
    @reviews = @reviews.verified_purchases if params[:verified_only] == "true"
    @reviews = @reviews.with_content if params[:with_content] == "true"
    @reviews = @reviews.with_media if params[:with_media] == "true"
    @reviews = @reviews.with_responses if params[:with_responses] == "true"
    @reviews = @reviews.high_quality if params[:high_quality] == "true"
    @reviews = @reviews.helpful if params[:helpful] == "true"

    # Apply search
    if params[:search].present?
      @reviews = @reviews.search_content(params[:search])
    end

    # Apply date range
    if params[:date_from].present? && params[:date_to].present?
      @reviews = @reviews.by_date_range(
        Date.parse(params[:date_from]),
        Date.parse(params[:date_to])
      )
    end

    # Apply sorting
    case params[:sort_by]
    when "helpful"
      @reviews = @reviews.order(helpful_count: :desc, created_at: :desc)
    when "rating_high"
      @reviews = @reviews.order(rating: :desc, created_at: :desc)
    when "rating_low"
      @reviews = @reviews.order(rating: :asc, created_at: :desc)
    when "quality"
      @reviews = @reviews.order("quality_score DESC NULLS LAST", created_at: :desc)
    else # 'recent' or default
      @reviews = @reviews.recent
    end

    # Pagination
    page = params[:page]&.to_i || 1
    per_page = [ params[:per_page]&.to_i || 10, 50 ].min
    offset = (page - 1) * per_page

    @total_count = @reviews.count
    @reviews = @reviews.limit(per_page).offset(offset)

    render_success(
      data: {
        reviews: serialize_reviews(@reviews),
        pagination: {
          page: page,
          per_page: per_page,
          total_count: @total_count,
          total_pages: (@total_count.to_f / per_page).ceil
        },
        filters_applied: {
          rating: params[:rating],
          sentiment: params[:sentiment],
          verified_only: params[:verified_only],
          with_content: params[:with_content],
          with_media: params[:with_media],
          with_responses: params[:with_responses],
          high_quality: params[:high_quality],
          helpful: params[:helpful],
          search: params[:search],
          sort_by: params[:sort_by] || "recent"
        }
      }
    )
  end

  # GET /api/v1/apps/:app_id/reviews/summary
  def summary
    cache = ReviewAggregationCache.find_by(app: @app)
    if cache.nil? || cache.stale?
      cache = ReviewAggregationCache.refresh_for_app(@app)
    end

    render_success(
      data: {
        average_rating: cache.average_rating,
        total_reviews: cache.total_reviews,
        rating_distribution: cache.rating_distribution,
        sentiment_distribution: cache.sentiment_distribution,
        verification_rate: cache.verification_rate,
        content_rate: cache.content_rate,
        overall_sentiment: cache.overall_sentiment,
        verified_reviews_count: cache.verified_reviews_count,
        reviews_with_content_count: cache.reviews_with_content_count,
        average_helpfulness: cache.average_helpfulness,
        monthly_review_velocity: cache.monthly_review_velocity,
        additional_metrics: cache.additional_metrics,
        last_updated: cache.last_updated
      }
    )
  end

  # GET /api/v1/reviews/:id
  def show
    render_success(
      data: {
        review: serialize_review(@app_review, include_extended: true)
      }
    )
  end

  # POST /api/v1/apps/:app_id/reviews
  def create
    # Check if user already has a review for this app
    existing_review = @app.app_reviews.find_by(account: current_user.account)
    if existing_review
      return render_error("You have already reviewed this app", status: :unprocessable_content)
    end

    @app_review = @app.app_reviews.build(review_params)
    @app_review.account = current_user.account
    @app_review.ip_address = request.remote_ip
    @app_review.user_agent = request.user_agent

    if @app_review.save
      # Handle media attachments if present
      handle_media_attachments if params[:media_attachments].present?

      render_success(
        data: { review: serialize_review(@app_review, include_extended: true) },
        message: "Review created successfully"
      )
    else
      render_validation_error(@app_review)
    end
  end

  # PATCH /api/v1/reviews/:id
  def update
    if @app_review.update(review_params)
      # Handle media attachments if present
      handle_media_attachments if params[:media_attachments].present?

      render_success(
        data: { review: serialize_review(@app_review, include_extended: true) },
        message: "Review updated successfully"
      )
    else
      render_validation_error(@app_review)
    end
  end

  # DELETE /api/v1/reviews/:id
  def destroy
    @app_review.destroy
    render_success(message: "Review deleted successfully")
  end

  # POST /api/v1/reviews/:id/vote
  def vote
    vote_type = params[:vote_type] # 'helpful' or 'unhelpful'
    is_helpful = vote_type == "helpful"

    # Find or initialize vote
    vote = @app_review.review_helpfulness_votes.find_or_initialize_by(
      account: current_user.account
    )

    # If vote already exists with same value, remove it (toggle behavior)
    if vote.persisted? && vote.is_helpful == is_helpful
      vote.destroy
      message = "Vote removed"
    else
      # Update vote
      vote.is_helpful = is_helpful
      vote.ip_address = request.remote_ip
      vote.voter_weight = calculate_voter_weight(current_user.account)
      vote.save!
      message = "Marked as #{vote_type}"
    end

    # Return updated review data
    @app_review.reload
    render_success(
      data: {
        review: serialize_review(@app_review),
        user_vote: vote.persisted? ? { is_helpful: vote.is_helpful } : nil
      },
      message: message
    )
  end

  # POST /api/v1/reviews/:id/flag
  def flag
    reason = params[:reason]

    if @app_review.flagged_for_review?
      return render_error("Review is already flagged", status: :unprocessable_content)
    end

    @app_review.flag_for_review!(reason, current_user.account)

    render_success(
      data: { review: serialize_review(@app_review) },
      message: "Review flagged for moderation"
    )
  end

  # POST /api/v1/reviews/:id/moderate
  def moderate
    unless current_user.has_permission?("reviews.moderate")
      return render_error("Insufficient permissions", status: :forbidden)
    end

    action = params[:action] # 'approve', 'reject', 'remove', 'restore'
    reason = params[:reason]

    case action
    when "approve"
      @app_review.approve_after_review!(current_user.account)
      message = "Review approved"
    when "reject"
      @app_review.update!(moderation_status: "rejected")
      @app_review.review_moderation_actions.create!(
        moderator: current_user.account,
        action_type: "reject",
        reason: reason,
        previous_status: "flagged",
        new_status: "rejected"
      )
      message = "Review rejected"
    when "remove"
      @app_review.remove_after_review!(reason, current_user.account)
      message = "Review removed"
    when "restore"
      @app_review.restore!(current_user.account, reason)
      message = "Review restored"
    else
      return render_error("Invalid moderation action", status: :unprocessable_content)
    end

    render_success(
      data: { review: serialize_review(@app_review) },
      message: message
    )
  end

  private

  def set_app
    @app = App.find(params[:app_id]) if params[:app_id]
    @app ||= @app_review.app if @app_review
  end

  def set_app_review
    @app_review = AppReview.find(params[:id])
  end

  def check_permissions
    # Users can only modify their own reviews unless they're moderators
    unless @app_review.account == current_user.account ||
           current_user.has_permission?("reviews.moderate")
      render_error("Insufficient permissions", status: :forbidden)
    end
  end

  def review_params
    params.require(:review).permit(:rating, :title, :content)
  end

  def handle_media_attachments
    return unless params[:media_attachments].is_a?(Array)

    params[:media_attachments].each do |media_params|
      @app_review.review_media_attachments.create!(
        media_type: media_params[:media_type],
        file_name: media_params[:file_name],
        file_path: media_params[:file_path],
        file_size: media_params[:file_size],
        mime_type: media_params[:mime_type],
        alt_text: media_params[:alt_text],
        sort_order: media_params[:sort_order] || 0
      )
    end
  end

  def calculate_voter_weight(account)
    # Base weight
    weight = 1.0

    # Account age bonus (max +0.5)
    account_age_days = (Time.current - account.created_at) / 1.day
    if account_age_days > 365
      weight += 0.5
    elsif account_age_days > 30
      weight += 0.25
    end

    # Verification bonus (+0.25)
    if AppSubscription.exists?(account: account, app: @app_review.app)
      weight += 0.25
    end

    # Quality reviewer bonus (based on previous review quality scores)
    avg_quality = account.app_reviews.average(:quality_score)
    if avg_quality && avg_quality > 4.0
      weight += 0.25
    end

    [ weight, 5.0 ].min.round(2)
  end

  def serialize_reviews(reviews)
    reviews.map { |review| serialize_review(review) }
  end

  def serialize_review(review, include_extended: false)
    base_data = {
      id: review.id,
      rating: review.rating,
      title: review.title,
      content: review.content,
      helpful_count: review.helpful_count,
      created_at: review.created_at,
      updated_at: review.updated_at,
      verified_purchase: review.verified_purchase,
      sentiment: review.sentiment,
      quality_score: review.quality_score,
      has_media: review.has_media?,
      has_responses: review.has_approved_responses?,
      author: {
        id: review.account.id,
        name: review.reviewer_name
      }
    }

    if include_extended
      base_data.merge!(
        moderation_status: review.moderation_status,
        flagged_for_review: review.flagged_for_review,
        flag_reason: review.flag_reason,
        admin_notes: review.admin_notes,
        media_attachments: review.review_media_attachments.publicly_visible.map do |attachment|
          {
            id: attachment.id,
            media_type: attachment.media_type,
            file_name: attachment.file_name,
            file_size: attachment.file_size_formatted,
            alt_text: attachment.alt_text,
            thumbnail_url: attachment.thumbnail_url,
            full_url: attachment.full_url
          }
        end,
        responses: review.approved_responses.map do |response|
          {
            id: response.id,
            response_type: response.response_type,
            content: response.content,
            created_at: response.created_at,
            author: {
              id: response.account.id,
              name: response.author_name
            }
          }
        end
      )
    end

    base_data
  end
end
