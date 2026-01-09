# frozen_string_literal: true

class Api::V1::Admin::ReviewModerationController < ApplicationController
  before_action :authenticate_request
  before_action :check_admin_permissions

  # GET /api/v1/admin/review_moderation/queue
  def queue
    @reviews = AppReview.includes(:account, :app, :review_moderation_actions)

    # Apply filters
    case params[:status]
    when "pending"
      @reviews = @reviews.pending_moderation
    when "flagged"
      @reviews = @reviews.flagged
    when "all"
      @reviews = @reviews.where.not(moderation_status: "approved")
    else # default to flagged
      @reviews = @reviews.flagged
    end

    # Filter by app if specified
    @reviews = @reviews.where(app_id: params[:app_id]) if params[:app_id].present?

    # Filter by rating
    @reviews = @reviews.by_rating(params[:rating]) if params[:rating].present?

    # Filter by date range
    if params[:date_from].present? && params[:date_to].present?
      @reviews = @reviews.by_date_range(
        Date.parse(params[:date_from]),
        Date.parse(params[:date_to])
      )
    end

    # Search
    if params[:search].present?
      @reviews = @reviews.search_content(params[:search])
    end

    # Apply sorting
    case params[:sort_by]
    when "rating"
      @reviews = @reviews.order(rating: :asc, created_at: :desc)
    when "helpful"
      @reviews = @reviews.order(helpful_count: :desc, created_at: :desc)
    when "flagged_date"
      @reviews = @reviews.order(updated_at: :desc)
    else # 'created' or default
      @reviews = @reviews.order(created_at: :desc)
    end

    # Pagination
    page = params[:page]&.to_i || 1
    per_page = [ params[:per_page]&.to_i || 20, 100 ].min
    offset = (page - 1) * per_page

    @total_count = @reviews.count
    @reviews = @reviews.limit(per_page).offset(offset)

    render_success({

        reviews: serialize_moderation_reviews(@reviews),
        pagination: {
          page: page,
          per_page: per_page,
          total_count: @total_count,
          total_pages: (@total_count.to_f / per_page).ceil
        },
        summary: moderation_queue_summary
      }
    )
  end

  # POST /api/v1/admin/review_moderation/bulk_action
  def bulk_action
    review_ids = params[:review_ids]
    action = params[:action] # 'approve', 'reject', 'remove', 'flag'
    reason = params[:reason]

    unless review_ids.is_a?(Array) && review_ids.any?
      return render_error("No reviews selected", status: :unprocessable_content)
    end

    reviews = AppReview.where(id: review_ids)
    results = { success: 0, failed: 0, errors: [] }

    reviews.each do |review|
      begin
        case action
        when "approve"
          review.approve_after_review!(current_user.account)
        when "reject"
          review.update!(moderation_status: "rejected")
          review.review_moderation_actions.create!(
            moderator: current_user.account,
            action_type: "reject",
            reason: reason,
            new_status: "rejected"
          )
        when "remove"
          review.remove_after_review!(reason, current_user.account)
        when "flag"
          review.flag_for_review!(reason, current_user.account) unless review.flagged?
        else
          results[:errors] << "Invalid action: #{action}"
          results[:failed] += 1
          next
        end

        results[:success] += 1
      rescue => e
        results[:errors] << "Review #{review.id}: #{e.message}"
        results[:failed] += 1
      end
    end

    render_success(
      data: results,
      message: "Bulk action completed: #{results[:success]} successful, #{results[:failed]} failed"
    )
  end

  # GET /api/v1/admin/review_moderation/analytics
  def analytics
    # Time range
    days_back = params[:days_back]&.to_i || 30
    start_date = days_back.days.ago

    analytics_data = {
      queue_stats: {
        total_flagged: AppReview.flagged.count,
        total_pending: AppReview.pending_moderation.count,
        total_removed: AppReview.where(removed: true).count,
        avg_resolution_time: calculate_avg_resolution_time(start_date)
      },
      moderation_actions: ReviewModerationAction.where("created_at >= ?", start_date)
                                               .group(:action_type)
                                               .count,
      moderator_activity: ReviewModerationAction.where("created_at >= ?", start_date)
                                               .joins(:moderator)
                                               .group("accounts.name")
                                               .count,
      daily_activity: ReviewModerationAction.where("created_at >= ?", start_date)
                                           .group_by_day(:created_at)
                                           .count,
      automated_vs_manual: ReviewModerationAction.where("created_at >= ?", start_date)
                                                 .group(:automated)
                                                 .count,
      confidence_distribution: ReviewModerationAction.where("created_at >= ? AND confidence_score IS NOT NULL", start_date)
                                                     .group_by do |action|
                                                       score = action.confidence_score.to_f
                                                       case score
                                                       when 0.0..0.3 then "low"
                                                       when 0.3..0.7 then "medium"
                                                       else "high"
                                                       end
                                                     end
                                                     .transform_values(&:count)
    }

    render_success(analytics_data)
  end

  # GET /api/v1/admin/review_moderation/history/:review_id
  def history
    review = AppReview.find(params[:review_id])
    actions = review.review_moderation_actions
                    .includes(:moderator)
                    .order(created_at: :desc)

    render_success({

        review: {
          id: review.id,
          title: review.display_title,
          rating: review.rating,
          current_status: review.moderation_status,
          created_at: review.created_at
        },
        actions: actions.map do |action|
          {
            id: action.id,
            action_type: action.action_type_display,
            moderator: action.moderator_name,
            reason: action.reason,
            notes: action.notes,
            automated: action.automated?,
            confidence_score: action.confidence_percentage,
            status_change: action.status_change_summary,
            created_at: action.created_at,
            time_ago: action.time_ago
          }
        end
      }
    )
  end

  # POST /api/v1/admin/review_moderation/settings
  def update_settings
    settings = params[:settings]

    # Update admin settings for moderation
    settings.each do |key, value|
      case key
      when "auto_flag_threshold"
        AdminSetting.set("review_auto_flag_threshold", value.to_f)
      when "auto_approve_threshold"
        AdminSetting.set("review_auto_approve_threshold", value.to_f)
      when "spam_keywords"
        AdminSetting.set("review_spam_keywords", value.join(","))
      when "require_verification_for_reviews"
        AdminSetting.set("require_verification_for_reviews", value.to_s)
      end
    end

    render_success(message: "Moderation settings updated successfully")
  end

  # GET /api/v1/admin/review_moderation/settings
  def settings
    settings = {
      auto_flag_threshold: AdminSetting.get("review_auto_flag_threshold", "2.0").to_f,
      auto_approve_threshold: AdminSetting.get("review_auto_approve_threshold", "4.0").to_f,
      spam_keywords: AdminSetting.get("review_spam_keywords", "").split(",").map(&:strip),
      require_verification_for_reviews: AdminSetting.get("require_verification_for_reviews", "false") == "true"
    }

    render_success({ settings: settings })
  end

  private

  def check_admin_permissions
    unless current_user.has_permission?("reviews.moderate")
      render_error("Insufficient permissions", status: :forbidden)
    end
  end

  def moderation_queue_summary
    {
      total_flagged: AppReview.flagged.count,
      total_pending: AppReview.pending_moderation.count,
      today_flagged: AppReview.flagged.where("updated_at >= ?", Date.current).count,
      this_week_resolved: ReviewModerationAction.where("created_at >= ?", 1.week.ago)
                                                 .where(action_type: [ "approve", "reject", "remove" ])
                                                 .count
    }
  end

  def calculate_avg_resolution_time(start_date)
    resolved_actions = ReviewModerationAction.where("created_at >= ?", start_date)
                                           .where(action_type: [ "approve", "reject", "remove" ])
                                           .joins(:app_review)

    return 0 if resolved_actions.empty?

    total_time = resolved_actions.sum do |action|
      flag_time = action.app_review.review_moderation_actions
                                   .where(action_type: "flag")
                                   .where("created_at <= ?", action.created_at)
                                   .maximum(:created_at)

      flag_time ? (action.created_at - flag_time) / 1.hour : 0
    end

    (total_time / resolved_actions.count).round(2)
  end

  def serialize_moderation_reviews(reviews)
    reviews.map do |review|
      {
        id: review.id,
        rating: review.rating,
        title: review.title,
        content_preview: review.content_summary(200),
        moderation_status: review.moderation_status,
        flagged_for_review: review.flagged_for_review,
        flag_reason: review.flag_reason,
        quality_score: review.quality_score,
        verified_purchase: review.verified_purchase,
        helpful_count: review.helpful_count,
        created_at: review.created_at,
        updated_at: review.updated_at,
        author: {
          id: review.account.id,
          name: review.reviewer_name
        },
        app: {
          id: review.app.id,
          name: review.app.name,
          slug: review.app.slug
        },
        latest_action: review.review_moderation_actions.order(created_at: :desc).first&.then do |action|
          {
            action_type: action.action_type_display,
            moderator: action.moderator_name,
            created_at: action.created_at,
            automated: action.automated?
          }
        end
      }
    end
  end
end
