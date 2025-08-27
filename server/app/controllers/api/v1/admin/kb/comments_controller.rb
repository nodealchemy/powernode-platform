# frozen_string_literal: true

class Api::V1::Admin::Kb::CommentsController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_kb_access
  before_action :set_comment, only: [:show, :approve, :reject, :spam, :destroy]

  # GET /api/v1/admin/kb/comments
  def index
    comments = KnowledgeBaseComment.includes(:user, :article)
    comments = apply_admin_filters(comments)
    comments = comments.page(params[:page]).per(params[:per_page] || 20)

    render_success(
      data: {
        comments: comments.map { |comment| serialize_comment_admin(comment) },
        pagination: pagination_meta(comments),
        stats: calculate_comment_stats
      },
      message: 'Comments retrieved successfully'
    )
  end

  # GET /api/v1/admin/kb/comments/:id
  def show
    return render_error('Comment not found', :not_found) unless @comment

    render_success(
      data: serialize_comment_detailed(@comment),
      message: 'Comment retrieved successfully'
    )
  end

  # POST /api/v1/admin/kb/comments/:id/approve
  def approve
    return render_error('Comment not found', :not_found) unless @comment

    @comment.approve!
    render_success(
      data: serialize_comment_admin(@comment),
      message: 'Comment approved successfully'
    )
  end

  # POST /api/v1/admin/kb/comments/:id/reject
  def reject
    return render_error('Comment not found', :not_found) unless @comment

    @comment.reject!
    render_success(
      data: serialize_comment_admin(@comment),
      message: 'Comment rejected successfully'
    )
  end

  # POST /api/v1/admin/kb/comments/:id/spam
  def spam
    return render_error('Comment not found', :not_found) unless @comment

    @comment.mark_as_spam!
    render_success(
      data: serialize_comment_admin(@comment),
      message: 'Comment marked as spam successfully'
    )
  end

  # DELETE /api/v1/admin/kb/comments/:id
  def destroy
    return render_error('Comment not found', :not_found) unless @comment

    @comment.destroy
    render_success(message: 'Comment deleted successfully')
  end

  private

  def set_comment
    @comment = KnowledgeBaseComment.find_by(id: params[:id])
  end

  def authorize_kb_access
    return render_error('Access denied', :forbidden) unless current_user.permissions.include?('kb.manage')
  end

  def apply_admin_filters(comments)
    comments = comments.where(status: params[:status]) if params[:status].present?
    comments = comments.where(article_id: params[:article_id]) if params[:article_id].present?
    comments = comments.where(user_id: params[:user_id]) if params[:user_id].present?
    comments = comments.where('content ILIKE ?', "%#{params[:search]}%") if params[:search].present?

    case params[:sort]
    when 'oldest'
      comments.order(:created_at)
    when 'likes'
      comments.order(likes_count: :desc)
    else
      comments.recent
    end
  end

  def serialize_comment_admin(comment)
    {
      id: comment.id,
      content: comment.content[0..200] + (comment.content.length > 200 ? '...' : ''),
      status: comment.status,
      user_name: comment.user.full_name,
      user_email: comment.user.email,
      article: {
        id: comment.article.id,
        title: comment.article.title
      },
      likes_count: comment.likes_count,
      replies_count: comment.replies_count,
      created_at: comment.created_at,
      is_reply: comment.reply?
    }
  end

  def serialize_comment_detailed(comment)
    {
      id: comment.id,
      content: comment.content,
      status: comment.status,
      user: {
        id: comment.user.id,
        name: comment.user.full_name,
        email: comment.user.email
      },
      article: {
        id: comment.article.id,
        title: comment.article.title,
        slug: comment.article.slug
      },
      parent_id: comment.parent_id,
      likes_count: comment.likes_count,
      replies_count: comment.replies_count,
      created_at: comment.created_at,
      updated_at: comment.updated_at,
      replies: comment.replies.recent.limit(5).map { |reply| serialize_comment_admin(reply) }
    }
  end

  def calculate_comment_stats
    {
      total: KnowledgeBaseComment.count,
      pending: KnowledgeBaseComment.pending.count,
      approved: KnowledgeBaseComment.approved.count,
      rejected: KnowledgeBaseComment.where(status: 'rejected').count,
      spam: KnowledgeBaseComment.where(status: 'spam').count
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