# frozen_string_literal: true

class Api::V1::Kb::CommentsController < ApplicationController
  skip_before_action :authenticate_request, only: [ :index, :show ]
  before_action :set_article, only: [ :index, :create ]
  before_action :set_comment, only: [ :show, :approve, :reject, :spam, :destroy, :moderate ]
  before_action :authorize_kb_moderate, only: [ :approve, :reject, :spam, :destroy, :moderate ]

  # GET /api/v1/kb/articles/:article_id/comments
  def index
    return render_error("Article not found", status: :not_found) unless @article

    comments = @article.comments.approved.top_level
      .includes(:author, :replies)
      .recent
      .page(params[:page])
      .per(params[:per_page] || 20)

    render_success(
      {
        comments: comments.map { |comment| serialize_comment_with_replies(comment) },
        pagination: pagination_meta(comments)
      }
    )
  end

  # POST /api/v1/kb/articles/:article_id/comments
  def create
    return render_error("Article not found", status: :not_found) unless @article
    return render_error("Access denied", status: :forbidden) unless @article.viewable_by?(current_user)

    comment = @article.comments.build(comment_params)
    comment.author = current_user

    if comment.save
      render_success(serialize_comment(comment))
    else
      render_validation_error(comment)
    end
  end

  # GET /api/v1/kb/comments/:id
  def show
    return render_error("Comment not found", status: :not_found) unless @comment&.approved?

    render_success(serialize_comment_with_replies(@comment))
  end

  # GET /api/v1/kb/comments/moderate
  def moderate
    # Admin view for comment moderation
    comments = KnowledgeBase::Comment.includes(:author, :article)
    comments = apply_admin_filters(comments)
    comments = comments.page(params[:page]).per(params[:per_page] || 20)

    render_success(
      comments: comments.map { |comment| serialize_comment_admin(comment) },
      pagination: pagination_meta(comments),
      stats: calculate_comment_stats
    )
  end

  # POST /api/v1/kb/comments/:id/approve
  def approve
    return render_error("Comment not found", status: :not_found) unless @comment

    @comment.approve!
    render_success(
      { comment: serialize_comment_admin(@comment) },
      message: "Comment approved successfully"
    )
  end

  # POST /api/v1/kb/comments/:id/reject
  def reject
    return render_error("Comment not found", status: :not_found) unless @comment

    @comment.reject!
    render_success(
      { comment: serialize_comment_admin(@comment) },
      message: "Comment rejected successfully"
    )
  end

  # POST /api/v1/kb/comments/:id/spam
  def spam
    return render_error("Comment not found", status: :not_found) unless @comment

    @comment.mark_as_spam!
    render_success(
      { comment: serialize_comment_admin(@comment) },
      message: "Comment marked as spam successfully"
    )
  end

  # DELETE /api/v1/kb/comments/:id
  def destroy
    return render_error("Comment not found", status: :not_found) unless @comment

    @comment.destroy
    render_success(message: "Comment deleted successfully")
  end

  private

  def set_article
    @article = KnowledgeBase::Article.find_by(id: params[:article_id])
  end

  def set_comment
    @comment = KnowledgeBase::Comment.find_by(id: params[:id])
  end

  def can_moderate_kb?
    current_user&.has_permission?("kb.moderate") ||
    current_user&.has_permission?("kb.manage")
  end

  def authorize_kb_moderate
    render_error("Access denied", status: :forbidden) unless can_moderate_kb?
  end

  def apply_admin_filters(comments)
    comments = comments.where(status: params[:status]) if params[:status].present?
    comments = comments.where(article_id: params[:article_id]) if params[:article_id].present?
    comments = comments.where(user_id: params[:user_id]) if params[:user_id].present?
    comments = comments.where("content ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(params[:search])}%") if params[:search].present?

    case params[:sort]
    when "oldest"
      comments.order(:created_at)
    when "likes"
      comments.order(helpful_count: :desc)
    else
      comments.recent
    end
  end

  def comment_params
    params.require(:comment).permit(:content, :parent_id)
  end

  def serialize_comment(comment)
    {
      id: comment.id,
      content: comment.content,
      user_name: comment.author.full_name,
      created_at: comment.created_at,
      helpful_count: comment.helpful_count,
      replies_count: comment.replies_count,
      is_reply: comment.reply?
    }
  end

  def serialize_comment_with_replies(comment)
    serialize_comment(comment).merge(
      replies: comment.replies.approved.recent.limit(5).map { |reply| serialize_comment(reply) }
    )
  end

  def serialize_comment_admin(comment)
    {
      id: comment.id,
      content: comment.content[0..200] + (comment.content.length > 200 ? "..." : ""),
      status: comment.status,
      user_name: comment.author.full_name,
      user_email: comment.author.email,
      article: {
        id: comment.article.id,
        title: comment.article.title
      },
      helpful_count: comment.helpful_count,
      replies_count: comment.replies_count,
      created_at: comment.created_at,
      is_reply: comment.reply?
    }
  end

  def calculate_comment_stats
    {
      total: KnowledgeBase::Comment.count,
      pending: KnowledgeBase::Comment.pending.count,
      approved: KnowledgeBase::Comment.approved.count,
      rejected: KnowledgeBase::Comment.where(status: "rejected").count,
      spam: KnowledgeBase::Comment.where(status: "spam").count
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
