# frozen_string_literal: true

class Api::V1::ReviewResponsesController < ApplicationController
  before_action :authenticate_request
  before_action :set_app_review, only: [ :index, :create ]
  before_action :set_review_response, only: [ :show, :update, :destroy, :approve, :reject ]
  before_action :check_permissions, only: [ :update, :destroy, :approve, :reject ]

  # GET /api/v1/app_reviews/:app_review_id/responses
  def index
    @responses = @app_review.review_responses.includes(:account, :approved_by)

    # Filter by status for non-moderators
    unless current_user.has_permission?("reviews.moderate")
      @responses = @responses.approved
    else
      @responses = @responses.where(status: params[:status]) if params[:status].present?
    end

    # Apply sorting
    case params[:sort_by]
    when "oldest"
      @responses = @responses.order(created_at: :asc)
    else # 'newest' or default
      @responses = @responses.order(created_at: :desc)
    end

    render_success(
      data: {
        responses: serialize_responses(@responses),
        review: {
          id: @app_review.id,
          title: @app_review.display_title,
          rating: @app_review.rating,
          author: @app_review.reviewer_name
        }
      }
    )
  end

  # GET /api/v1/review_responses/:id
  def show
    render_success(
      data: { response: serialize_response(@review_response, include_extended: true) }
    )
  end

  # POST /api/v1/app_reviews/:app_review_id/responses
  def create
    @review_response = @app_review.review_responses.build(response_params)
    @review_response.account = current_user.account

    # Auto-approve for certain users or set to pending
    if can_auto_approve?
      @review_response.status = "approved"
      @review_response.approved_at = Time.current
      @review_response.approved_by = current_user.account
    else
      @review_response.status = "pending"
    end

    if @review_response.save
      render_success(
        data: { response: serialize_response(@review_response, include_extended: true) },
        message: @review_response.approved? ?
          "Response posted successfully" :
          "Response submitted for approval"
      )
    else
      render_validation_error(@review_response)
    end
  end

  # PATCH /api/v1/review_responses/:id
  def update
    if @review_response.update(response_params)
      # Reset to pending if content was changed and not auto-approved
      if @review_response.saved_change_to_content? && !can_auto_approve?
        @review_response.update!(status: "pending", approved_at: nil, approved_by: nil)
      end

      render_success(
        data: { response: serialize_response(@review_response, include_extended: true) },
        message: "Response updated successfully"
      )
    else
      render_validation_error(@review_response)
    end
  end

  # DELETE /api/v1/review_responses/:id
  def destroy
    @review_response.destroy
    render_success(message: "Response deleted successfully")
  end

  # POST /api/v1/review_responses/:id/approve
  def approve
    unless current_user.has_permission?("reviews.moderate")
      return render_error("Insufficient permissions", status: :forbidden)
    end

    if @review_response.approved?
      return render_error("Response is already approved", status: :unprocessable_content)
    end

    @review_response.approve!(current_user.account)

    render_success(
      data: { response: serialize_response(@review_response) },
      message: "Response approved successfully"
    )
  end

  # POST /api/v1/review_responses/:id/reject
  def reject
    unless current_user.has_permission?("reviews.moderate")
      return render_error("Insufficient permissions", status: :forbidden)
    end

    if @review_response.rejected?
      return render_error("Response is already rejected", status: :unprocessable_content)
    end

    reason = params[:reason]
    @review_response.reject!(current_user.account, reason)

    render_success(
      data: { response: serialize_response(@review_response) },
      message: "Response rejected"
    )
  end

  private

  def set_app_review
    @app_review = ::Marketplace::Review.find(params[:app_review_id])
  end

  def set_review_response
    @review_response = ReviewResponse.find(params[:id])
  end

  def check_permissions
    # Users can only modify their own responses unless they're moderators
    unless @review_response.account == current_user.account ||
           current_user.has_permission?("reviews.moderate")
      render_error("Insufficient permissions", status: :forbidden)
    end
  end

  def response_params
    params.require(:response).permit(:content, :response_type)
  end

  def can_auto_approve?
    # Auto-approve if user is the app owner or has moderation permissions
    app = @app_review.app
    current_user.account == app.account ||
    current_user.has_permission?("reviews.moderate")
  end

  def serialize_responses(responses)
    responses.map { |response| serialize_response(response) }
  end

  def serialize_response(response, include_extended: false)
    base_data = {
      id: response.id,
      content: response.content,
      response_type: response.response_type,
      response_type_display: response.response_type_display,
      status: response.status,
      created_at: response.created_at,
      updated_at: response.updated_at,
      author: {
        id: response.account.id,
        name: response.author_name
      }
    }

    if include_extended
      base_data.merge!(
        approved_at: response.approved_at,
        approved_by: response.approved_by&.name,
        metadata: response.metadata,
        word_count: response.word_count,
        time_ago: response.time_ago
      )
    end

    base_data
  end
end
