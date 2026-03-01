# frozen_string_literal: true

module Api
  module V1
    module Internal
      module Ai
        class CodeReviewsController < InternalBaseController
          # POST /api/v1/internal/ai/code_reviews/:review_id/comments
          def create_comments
            review = ::Ai::TaskReview.find(params[:review_id])
            comments = (params[:comments] || []).map do |comment_params|
              review.account.ai_code_review_comments.create!(
                task_review: review,
                file_path: comment_params[:file_path],
                line_start: comment_params[:line_start],
                line_end: comment_params[:line_end],
                comment_type: comment_params[:comment_type],
                severity: comment_params[:severity],
                content: comment_params[:content],
                suggested_fix: comment_params[:suggested_fix],
                category: comment_params[:category],
                agent_id: comment_params[:agent_id],
                metadata: comment_params[:metadata] || {}
              )
            end

            render_success({ comments_created: comments.size })
          rescue ActiveRecord::RecordNotFound
            render_not_found("Task Review")
          end
        end
      end
    end
  end
end
