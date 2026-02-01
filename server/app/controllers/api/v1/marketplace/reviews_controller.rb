# frozen_string_literal: true

module Api
  module V1
    module Marketplace
      class ReviewsController < ApplicationController
        skip_before_action :authenticate_request, only: [ :index, :show ]
        before_action :authenticate_optional, only: [ :index, :show ]
        before_action :set_reviewable, only: [ :index, :create ]
        before_action :set_review, only: [ :show, :update, :destroy, :helpful ]

        # GET /api/v1/marketplace/reviews
        # Lists reviews for a specific item or all reviews
        def index
          reviews = if @reviewable
                      @reviewable.marketplace_reviews
          else
                      MarketplaceReview.all
          end

          reviews = reviews.approved unless params[:include_pending] == "true" && can_moderate?
          reviews = reviews.by_rating(params[:rating].to_i) if params[:rating].present?
          reviews = reviews.verified if params[:verified] == "true"

          # Ordering
          case params[:sort]
          when "helpful"
            reviews = reviews.most_helpful
          when "rating_high"
            reviews = reviews.order(rating: :desc)
          when "rating_low"
            reviews = reviews.order(rating: :asc)
          else
            reviews = reviews.recent
          end

          # Pagination
          pagination = pagination_params
          total_count = reviews.count
          reviews = reviews.offset((pagination[:page] - 1) * pagination[:per_page]).limit(pagination[:per_page])

          render_success(
            reviews.map { |r| serialize_review(r) },
            meta: {
              current_page: pagination[:page],
              per_page: pagination[:per_page],
              total_count: total_count,
              total_pages: (total_count.to_f / pagination[:per_page]).ceil,
              rating_distribution: @reviewable&.rating_distribution || {}
            }
          )
        end

        # GET /api/v1/marketplace/reviews/:id
        def show
          render_success(serialize_review(@review, detailed: true))
        end

        # POST /api/v1/marketplace/reviews
        # Creates a new review for an item
        def create
          return render_error("Authentication required", :unauthorized) unless current_user
          return render_error("Item not found", :not_found) unless @reviewable

          # Check if already reviewed
          if @reviewable.reviewed_by?(current_account)
            return render_error("You have already reviewed this item", :unprocessable_content)
          end

          # Check if user has a subscription (verified purchase)
          verified = has_active_subscription?(@reviewable)

          review = MarketplaceReview.new(
            reviewable: @reviewable,
            account: current_account,
            user: current_user,
            rating: params[:rating],
            title: params[:title],
            content: params[:content],
            verified_purchase: verified,
            moderation_status: "pending"
          )

          if review.save
            render_success(serialize_review(review), status: :created)
          else
            render_validation_error(review)
          end
        end

        # PATCH /api/v1/marketplace/reviews/:id
        def update
          return render_error("Authentication required", :unauthorized) unless current_user
          return render_error("Cannot edit this review", :forbidden) unless can_edit_review?(@review)

          if @review.update(review_params)
            # Reset moderation status on edit
            @review.update(moderation_status: "pending")
            render_success(serialize_review(@review))
          else
            render_validation_error(@review)
          end
        end

        # DELETE /api/v1/marketplace/reviews/:id
        def destroy
          return render_error("Authentication required", :unauthorized) unless current_user
          return render_error("Cannot delete this review", :forbidden) unless can_delete_review?(@review)

          @review.destroy
          render_success({ message: "Review deleted successfully" })
        end

        # POST /api/v1/marketplace/reviews/:id/helpful
        def helpful
          return render_error("Authentication required", :unauthorized) unless current_user
          return render_error("Cannot mark your own review as helpful", :unprocessable_content) if @review.user_id == current_user.id

          @review.increment_helpful!
          render_success({ helpful_count: @review.helpful_count })
        end

        # Moderation endpoints (admin only)

        # POST /api/v1/marketplace/reviews/:id/approve
        def approve
          return render_error("Forbidden", :forbidden) unless can_moderate?

          @review = MarketplaceReview.find(params[:id])
          @review.approve!
          render_success(serialize_review(@review))
        end

        # POST /api/v1/marketplace/reviews/:id/reject
        def reject
          return render_error("Forbidden", :forbidden) unless can_moderate?

          @review = MarketplaceReview.find(params[:id])
          @review.reject!
          render_success(serialize_review(@review))
        end

        # POST /api/v1/marketplace/reviews/:id/flag
        def flag
          return render_error("Authentication required", :unauthorized) unless current_user

          @review = MarketplaceReview.find(params[:id])
          @review.flag!
          render_success({ message: "Review flagged for moderation" })
        end

        private

        def set_reviewable
          return unless params[:item_type].present? && params[:item_id].present?

          @reviewable = case params[:item_type]
          when "template", "workflow_template"
                         ::Ai::WorkflowTemplate.find_by(id: params[:item_id])
          when "integration", "integration_template"
                         ::Devops::IntegrationTemplate.find_by(id: params[:item_id])
          when "pipeline_template"
                         ::Devops::PipelineTemplate.find_by(id: params[:item_id])
          when "prompt_template"
                         ::Shared::PromptTemplate.find_by(id: params[:item_id])
          end
        end

        def set_review
          @review = MarketplaceReview.find_by(id: params[:id])
          render_error("Review not found", :not_found) unless @review
        end

        def review_params
          params.permit(:rating, :title, :content)
        end

        def serialize_review(review, detailed: false)
          data = {
            id: review.id,
            rating: review.rating,
            title: review.title,
            content: review.content,
            verified_purchase: review.verified_purchase,
            helpful_count: review.helpful_count,
            moderation_status: review.moderation_status,
            created_at: review.created_at.iso8601,
            updated_at: review.updated_at.iso8601,
            author: {
              id: review.user.id,
              name: review.user.full_name,
              avatar: review.user.avatar_url
            }
          }

          if detailed
            data[:reviewable] = {
              id: review.reviewable_id,
              type: review.reviewable_type,
              name: review.reviewable&.name
            }
          end

          data
        end

        def can_edit_review?(review)
          return false unless current_user
          review.account_id == current_account.id || can_moderate?
        end

        def can_delete_review?(review)
          return false unless current_user
          review.account_id == current_account.id || can_moderate?
        end

        def can_moderate?
          current_user&.has_permission?("marketplace.moderate")
        end

        def has_active_subscription?(item)
          return false unless current_account

          ::Marketplace::Subscription.exists?(
            account: current_account,
            subscribable_type: item.class.name,
            subscribable_id: item.id,
            status: "active"
          )
        end

        def authenticate_optional
          header = request.headers["Authorization"]
          return unless header

          header = header.split(" ").last

          begin
            payload = Security::JwtService.decode(header)

            case payload[:type]
            when "access"
              @current_user = User.find(payload[:sub])
              @current_account = @current_user.account
              @current_jwt_payload = payload
            end
          rescue StandardError => e
            Rails.logger.debug "Optional authentication failed: #{e.message}"
            @current_user = nil
            @current_account = nil
          end
        end
      end
    end
  end
end
