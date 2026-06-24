# frozen_string_literal: true

class Api::V1::Kb::AttachmentsController < ApplicationController
  skip_before_action :authenticate_request, only: [ :show ]
  before_action :authenticate_optional, only: [ :show ]
  before_action :set_attachment, only: [ :show, :destroy ]
  before_action :authorize_kb_edit, only: [ :create, :destroy ]

  # GET /api/v1/kb/attachments/:id
  def show
    return render_error("Attachment not found", status: :not_found) unless @attachment

    article = @attachment.article

    # Tenancy gate (applies even to editors): an attachment on an account-owned
    # article is only reachable from within its owning account. Globals
    # (account_id nil) fall through to the existing editor/public policy.
    if article&.account_id.present? && current_user&.account_id != article.account_id
      return render_error("Access denied", status: :forbidden)
    end

    # For public access, ensure the attachment belongs to a viewable article.
    unless can_edit_kb?
      return render_error("Access denied", status: :forbidden) unless article&.viewable_by?(current_user)
    end

    render_success({
      attachment: serialize_attachment(@attachment)
    })
  end

  # POST /api/v1/kb/attachments
  def create
    return render_error("No file provided", status: :bad_request) unless params[:file].present?

    attachment = KnowledgeBase::Attachment.new(attachment_params)
    attachment.uploaded_by = current_user

    if attachment.save
      render_success(data: {
        attachment: serialize_attachment(attachment),
        url: attachment.file_url
      })
    else
      render_validation_error(attachment)
    end
  rescue StandardError => e
    render_internal_error("Upload failed", exception: e)
  end

  # DELETE /api/v1/kb/attachments/:id
  def destroy
    return render_error("Attachment not found", status: :not_found) unless @attachment

    if @attachment.destroy
      render_success(message: "Attachment deleted successfully")
    else
      render_error("Failed to delete attachment", status: :internal_server_error)
    end
  end

  private

  def set_attachment
    @attachment = KnowledgeBase::Attachment.find_by(id: params[:id])
  end

  def can_edit_kb?
    current_user&.has_permission?("kb.update") ||
    current_user&.has_permission?("kb.manage")
  end

  def authorize_kb_edit
    render_error("Access denied", status: :forbidden) unless can_edit_kb?
  end

  def attachment_params
    {
      file: params[:file],
      article_id: params[:article_id],
      uploaded_by: current_user
    }
  end

  def serialize_attachment(attachment)
    {
      id: attachment.id,
      filename: attachment.filename,
      content_type: attachment.content_type,
      size: attachment.file_size,
      url: attachment.file_url,
      created_at: attachment.created_at,
      uploader_name: attachment.uploaded_by&.full_name
    }
  end
end
