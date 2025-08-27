# frozen_string_literal: true

class Api::V1::Kb::CommentsController < ApplicationController
  skip_before_action :authenticate_request, only: [:index, :show]
  before_action :authenticate_user!, only: [:create]
  before_action :set_article, only: [:index, :create]
  before_action :set_comment, only: [:show]

  # GET /api/v1/kb/articles/:article_id/comments
  def index
    return render_error('Article not found', status: :not_found) unless @article

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
    return render_error('Article not found', status: :not_found) unless @article
    return render_error('Access denied', status: :forbidden) unless @article.viewable_by?(current_user)

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
    return render_error('Comment not found', status: :not_found) unless @comment&.approved?

    render_success(serialize_comment_with_replies(@comment))
  end

  private

  def set_article
    @article = KnowledgeBaseArticle.find_by(id: params[:article_id])
  end

  def set_comment
    @comment = KnowledgeBaseComment.find_by(id: params[:id])
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
      likes_count: comment.likes_count,
      replies_count: comment.replies_count,
      is_reply: comment.reply?
    }
  end

  def serialize_comment_with_replies(comment)
    serialize_comment(comment).merge(
      replies: comment.replies.approved.recent.limit(5).map { |reply| serialize_comment(reply) }
    )
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