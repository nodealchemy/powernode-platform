# frozen_string_literal: true

class Api::V1::Kb::AttachmentsController < ApplicationController
  skip_before_action :authenticate_request, only: [ :show ]
  before_action :set_attachment, only: [ :show, :destroy ]
  before_action :authorize_kb_edit, only: [ :create, :destroy ]

  # GET /api/v1/kb/attachments/:id
  def show
    return render_error("Attachment not found", status: :not_found) unless @attachment

    # For public access, ensure the attachment belongs to a published article
    unless can_edit_kb?
      article = @attachment.attachable
      return render_error("Access denied", status: :forbidden) unless article&.viewable_by?(current_user)
    end

    render_success({
      attachment: serialize_attachment(@attachment)
    })
  end

  # POST /api/v1/kb/attachments
  def create
    return render_error("No file provided", status: :bad_request) unless params[:file].present?

    attachment = KnowledgeBaseAttachment.new(attachment_params)
    attachment.uploader = current_user

    if attachment.save
      render_success({
        attachment: serialize_attachment(attachment),
        url: attachment.file_url
      }, "File uploaded successfully")
    else
      render_validation_error(attachment)
    end
  rescue StandardError => e
    Rails.logger.error "Attachment upload failed: #{e.message}"
    render_error("Upload failed: #{e.message}", status: :internal_server_error)
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
    @attachment = KnowledgeBaseAttachment.find_by(id: params[:id])
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
      uploader_name: attachment.uploader&.full_name
    }
  end
end
